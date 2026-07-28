# ── PUBLIC: MEMORY FUNCTIONS ───────────────────────────────────────────────

function Get-OpsMemoryFile {
    <#
    .SYNOPSIS
    Returns the path to the JSONL memory file, creating the directory if needed.
    .OUTPUTS
    String path to the memory file.
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:OpsMemoryRoot)) { $null = New-Item -Path $script:OpsMemoryRoot -ItemType Directory -Force }
    return $script:OpsMemoryFile
}

function Read-OpsMemory {
    <#
    .SYNOPSIS
    Reads all memory entries from the JSONL store and returns typed OpsMemoryEntry objects.
    .OUTPUTS
    OpsMemoryEntry[]
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:OpsMemoryFile)) { return @() }
    Get-Content -Path $script:OpsMemoryFile -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        try {
            $untypedMap = $_ | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            [OpsMemoryEntry]::new($untypedMap)
        } catch { Write-Verbose "Memory entry parse skipped: $($_.Exception.Message)" }
    }
}

function Add-OpsMemory {
    <#
    .SYNOPSIS
    Saves a memory entry with type, tags, confidence, and optional pinned status.
    .OUTPUTS
    OpsMemoryEntry instance saved to the JSONL store.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Text,
        [ValidateSet('preference', 'runbook', 'session', 'web', 'sysops', 'note')][string]$Type = 'note',
        [string[]]$Tag = @(),
        [string]$Source = 'manual',
        [ValidateSet('low', 'medium', 'high', 'user')][string]$Confidence = 'user',
        [switch]$Pinned,
        [switch]$NoEmbedding
    )
    $joined = ($Text -join ' ').Trim()
    if (-not $joined) { throw 'Payload buffer verification empty.' }

    $embedding = $null
    if (-not $NoEmbedding) {
        $embedding = Invoke-OpsAIEmbedding -Text $joined
    }

    $map = [hashtable]@{
        Id         = Format-OpsMemoryId
        Type       = $Type
        Tags       = @($Tag)
        Text       = ($joined | Protect-OpsSensitiveText | Out-String).Trim()
        Source     = $Source
        Created    = (Get-Date).ToString('o')
        Confidence = $Confidence
        Pinned     = [bool]$Pinned
        Embedding  = $embedding
    }

    if ($PSCmdlet.ShouldProcess("Memory entry: $(Format-OpsMemorySnippet -Text $joined)", 'Save memory')) {
        $typedInstance = [OpsMemoryEntry]::new($map)
        ($typedInstance | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path (Get-OpsMemoryFile) -Encoding UTF8
        return $typedInstance
    }
}

function Update-OpsMemoryEmbeddings {
    <#
    .SYNOPSIS
    Backfills missing embeddings for existing memory entries.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([int]$BatchSize = 20)
    $items = @(Read-OpsMemory)
    $toUpdate = @($items | Where-Object { $null -eq $_.Embedding })
    if (-not $toUpdate) { Write-OpsHeader "  [INFO] All memory entries already have embeddings." Gray; return }

    Write-OpsHeader "  [INFO] Backfilling embeddings for $($toUpdate.Count) entries..." Yellow
    $updatedCount = 0
    $newItems = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $items) {
        if ($null -eq $item.Embedding -and $updatedCount -lt $BatchSize) {
            Write-Host "    - Indexing: $(Format-OpsMemorySnippet -Text $item.Text -MaxLength 60)" -ForegroundColor Gray
            $item.Embedding = Invoke-OpsAIEmbedding -Text $item.Text
            $updatedCount++
        }
        $newItems.Add($item)
    }

    if ($PSCmdlet.ShouldProcess("$(Get-OpsMemoryFile)", "Update $updatedCount embeddings")) {
        $lines = @(foreach ($ni in $newItems) { $ni | ConvertTo-Json -Compress -Depth 6 })
        $lines | Set-Content -Path (Get-OpsMemoryFile) -Encoding UTF8
        Write-OpsHeader "  [PASS] Successfully updated $updatedCount entries." Green
    }
}

function Search-OpsMemory {
    <#
    .SYNOPSIS
    Searches memory entries using hybrid keyword + semantic similarity scoring.
    .OUTPUTS
    PSCustomObject scored results, or OpsMemoryEntry[] when no query is given.
    #>
    [CmdletBinding()] param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Query = @(), [int]$First = 8, [switch]$Pinned, [switch]$NoSemantic)
    $queryText = ($Query -join ' ').Trim()
    $items = @(Read-OpsMemory)
    if ($Pinned) { $items = @($items | Where-Object { $_.Pinned }) }
    if (-not $items) { return }
    if (-not $queryText) { $items | Sort-Object Created -Descending | Select-Object -First $First; return }

    $queryEmbedding = $null
    if (-not $NoSemantic) {
        $queryEmbedding = Invoke-OpsAIEmbedding -Text $queryText
    }

    $terms = @(Get-OpsMemorySearchTerm -Text $queryText)

    @(foreach ($item in $items) {
        $keywordScore = 0
        $semanticScore = 0

        # 1. Keyword Scoring
        $haystack = "$($item.Type) $((@($item.Tags) -join ' ')) $($item.Text)".ToLowerInvariant()
        foreach ($term in $terms) { if ($haystack.Contains($term)) { $keywordScore++ } }

        # 2. Semantic Scoring
        if ($null -ne $queryEmbedding -and $null -ne $item.Embedding) {
            $similarity = Get-OpsVectorSimilarity -VectorA $queryEmbedding -VectorB $item.Embedding
            # Map 0.0-1.0 similarity to a score weight. Threshold of 0.7 for "relevant"
            if ($similarity -gt 0.7) {
                $semanticScore = [Math]::Round($similarity * 5, 2)
            }
        }

        $totalScore = $keywordScore + $semanticScore
        if ($item.Pinned) { $totalScore += 2 }

        if ($totalScore -gt 0) {
            [PSCustomObject]@{
                Score      = $totalScore
                Semantic   = $semanticScore
                Keyword    = $keywordScore
                Id         = $item.Id
                Type       = $item.Type
                Tags       = $item.Tags
                Text       = $item.Text
                Source     = $item.Source
                Created    = $item.Created
                Confidence = $item.Confidence
                Pinned     = $item.Pinned
            }
        }
    }) | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Created'; Descending = $true } | Select-Object -First $First
}

function Get-OpsMemoryMap {
    <#
    .SYNOPSIS
    Returns memory entries filtered by tag and pinned status, sorted by creation date.
    .OUTPUTS
    OpsMemoryEntry[]
    #>
    [CmdletBinding()]
    param([string]$Tag, [switch]$Pinned, [int]$First = 40)
    $items = @(Read-OpsMemory)
    if ($Pinned) { $items = @($items | Where-Object { $_.Pinned }) }
    if ($Tag) { $items = @($items | Where-Object { $_.Tags -and @($_.Tags) -contains $Tag }) }
    $items | Sort-Object Created -Descending | Select-Object -First $First
}
