# ── PUBLIC: AI FUNCTIONS ───────────────────────────────────────────────────

function Get-OpsAIStatus {
    <#
    .SYNOPSIS
    Returns reachable Ollama models and their sizes from the local endpoint.
    .OUTPUTS
    PSCustomObject with Endpoint, Status, Model, SizeGB, and Modified.
    #>
    [CmdletBinding()]
    param([string]$Endpoint = $script:OpsDefaultAIEndpoint)
    return Invoke-OpsCachedData -Key "ai_status_$Endpoint" -ExpirySeconds 15 -ScriptBlock {
        try {
            $models = (Invoke-RestMethod -Uri "$Endpoint/api/tags" -TimeoutSec 5 -ErrorAction Stop).models
            if (-not $models) { return @() }
            foreach ($model in $models) {
                [PSCustomObject]@{ Endpoint = $Endpoint; Status = 'Reachable'; Model = $model.name; SizeGB = [Math]::Round($model.size / 1GB, 2); Modified = $model.modified_at }
            }
        } catch {
            [PSCustomObject]@{ Endpoint = $Endpoint; Status = 'Unavailable'; Model = ''; SizeGB = ''; Modified = $_.Exception.Message }
        }
    }
}

function Invoke-OpsAIEmbedding {
    <#
    .SYNOPSIS
    Generates a vector embedding for the given text using local Ollama.
    .OUTPUTS
    Float array representing the embedding vector.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Model = $script:OpsDefaultAIModel,
        [string]$Endpoint = $script:OpsDefaultAIEndpoint
    )
    try {
        $payload = @{ model = $Model; prompt = $Text } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$Endpoint/api/embeddings" -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop
        return [float[]]$response.embedding
    } catch {
        Write-Verbose "AI embedding failure: $($_.Exception.Message)"
        return $null
    }
}

function Get-OpsVectorSimilarity {
    <#
    .SYNOPSIS
    Calculates cosine similarity between two numeric vectors.
    .OUTPUTS
    Float between 0 and 1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][float[]]$VectorA,
        [Parameter(Mandatory = $true)][float[]]$VectorB
    )
    if ($VectorA.Count -ne $VectorB.Count) { return 0 }
    $dotProduct = 0; $magA = 0; $magB = 0
    for ($i = 0; $i -lt $VectorA.Count; $i++) {
        $dotProduct += $VectorA[$i] * $VectorB[$i]
        $magA += $VectorA[$i] * $VectorA[$i]
        $magB += $VectorB[$i] * $VectorB[$i]
    }
    $magA = [Math]::Sqrt($magA); $magB = [Math]::Sqrt($magB)
    if ($magA -eq 0 -or $magB -eq 0) { return 0 }
    return $dotProduct / ($magA * $magB)
}

function Get-OpsAIIntent {
    <#
    .SYNOPSIS
    Classifies an instruction into an intent category (Research, Shell, Compare, Explain, AnalyzeData).
    .OUTPUTS
    String containing the matched intent category name.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Instruction)
    if ([string]::IsNullOrWhiteSpace($Instruction)) { return 'AnalyzeData' }
    $text = $Instruction.ToLowerInvariant()
    if ($text -match '\b(search|web|online|latest|current|look up|lookup|research)\b') { return 'Research' }
    if ($text -match '\b(command|script|cmdlet|syntax|powershell|how do i|how to|fix|change|install|remove|delete|start|stop|restart)\b') { return 'Shell' }
    if ($text -match '\b(compare|changed|since|history|previous|trend)\b') { return 'Compare' }
    if ($text -match '\b(summarize|summary|explain|why|what does)\b') { return 'Explain' }
    return 'AnalyzeData'
}

function Get-OpsAIDataProfile {
    <#
    .SYNOPSIS
    Profiles input data to determine kind (Table, Object, Text, Empty), row count, and column names.
    .OUTPUTS
    PSCustomObject with Kind, Rows, and Columns properties.
    #>
    [CmdletBinding()]
    param([object[]]$InputObject = @())
    $rows = @($InputObject | Where-Object { $null -ne $_ })
    if (-not $rows) { return [PSCustomObject]@{ Kind = 'Empty'; Rows = 0; Columns = '' } }
    if ($rows[0] -is [string]) { return [PSCustomObject]@{ Kind = 'Text'; Rows = $rows.Count; Columns = 'Text' } }
    $cols = @($rows[0].PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name -First 24)
    [PSCustomObject]@{ Kind = if ($cols.Count -gt 1) { 'Table' } else { 'Object' }; Rows = $rows.Count; Columns = ($cols -join ', ') }
}

function Build-OpsAIMemoryContext {
    <#
    .SYNOPSIS
    Assembles pinned and relevant memory entries into a text block for AI context.
    .OUTPUTS
    String containing formatted memory entries or empty string if none found.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', 'Read-only data assembly from existing memory')]
    param([string]$Query, [int]$First = 5)
    $items = @(Search-OpsMemory -Pinned -First 3)
    if ($Query) { $items += @(Search-OpsMemory -Query $Query -First $First) }
    $selected = @(foreach ($item in $items) { if ($item.Id) { $item } }) | Select-Object -First $First
    if (-not $selected) { return '' }
    $lines = [System.Collections.Generic.List[string]]::new(); $lines.Add('Relevant local memory:')
    foreach ($item in $selected) { $lines.Add("- [$($item.Type)] $(Format-OpsMemorySnippet -Text $item.Text -MaxLength 220)") }
    return ($lines -join [Environment]::NewLine)
}

function Build-OpsAIContextPacket {
    <#
    .SYNOPSIS
    Builds a full context envelope with intent, mode, data profile, and memory for AI queries.
    .OUTPUTS
    PSCustomObject with Intent, Mode, and Text properties.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', 'Read-only data assembly, no system state change')]
    param(
        [string]$Instruction,
        [object[]]$InputObject = @(),
        [int]$MemoryLimit = 5,
        [switch]$NoMemory,
        [switch]$FullEnv
    )
    $intent = Get-OpsAIIntent -Instruction $Instruction; $dataProfile = Get-OpsAIDataProfile -InputObject $InputObject
    $mode = 'Fast'
    if ($Instruction -match '(?i)\b(deep|thorough|investigate|full|history|compare)\b') { $mode = 'Deep' }
    elseif ($intent -in @('Research', 'Compare')) { $mode = 'Balanced' }

    $lines = [System.Collections.Generic.List[string]]::new(); $lines.Add('Context envelope:')
    $lines.Add("- Mode: $mode"); $lines.Add("- Intent: $intent"); $lines.Add("- Data kind: $($dataProfile.Kind)"); $lines.Add("- Rows: $($dataProfile.Rows)")
    if ($dataProfile.Columns) { $lines.Add("- Columns: $($dataProfile.Columns)") }

    if ($FullEnv) {
        $health = Get-OpsHealth
        $lines.Add("- Ambient Time: $((Get-Date).ToString('o'))")
        $lines.Add("- System Health: CPU $($health.'CPU Load'), RAM $($health.'RAM Usage'), Procs $($health.Processes)")
        if ($null -ne $Error -and $Error.Count -gt 0) {
            $lines.Add("- Last Error: $($Error[0].Exception.Message)")
        }
    }

    if (-not $NoMemory) { $mem = Build-OpsAIMemoryContext -Query $Instruction -First $MemoryLimit; if ($mem) { $lines.Add(''); $lines.Add($mem) } }
    [PSCustomObject]@{ Intent = $intent; Mode = $mode; Text = ($lines -join [Environment]::NewLine) }
}

function Invoke-OpsAI {
    <#
    .SYNOPSIS
    Sends pipeline data and a question to a local Ollama model with streaming output.
    .OUTPUTS
    Streams AI response text to the console; optionally stores Q&A in memory.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', 'Intentional streaming output to console')]
    [CmdletBinding()] param([Parameter(ValueFromPipeline = $true, Mandatory = $true)]$InputData, [Parameter(Position = 0)][string]$Instruction = 'Analyze this data.', [string]$Model = $script:OpsDefaultAIModel, [int]$TimeoutSec = 120, [int]$MaxRetries = 0, [switch]$RedactSensitive, [switch]$Remember, [switch]$NoMemory, [int]$MemoryLimit = 5, [switch]$FullEnv)
    begin { $dataBuffer = [System.Collections.Generic.List[object]]::new() }
    process { if ($null -ne $_) { $dataBuffer.Add($_) } elseif ($null -ne $InputData) { $dataBuffer.Add($InputData) } }
    end {
        $stringifiedData = $dataBuffer | Out-String
        if ($RedactSensitive) {
            $stringifiedData = $stringifiedData | Protect-OpsSensitiveText
        }
        $ctx = Build-OpsAIContextPacket -Instruction $Instruction -InputObject $dataBuffer.ToArray() -MemoryLimit $MemoryLimit -NoMemory:$NoMemory -FullEnv:$FullEnv
        $tools = Get-OpsCapabilitiesMap
        $contract = "You are PowershellOps AI, a fast local PowerShell/SysOps assistant.`nUse the context envelope, relevant memory, and pipeline data as evidence.`n$tools`n`nDefault to a concise answer. Expand only when requested.`nIf pipeline data is present, answer from it first and preserve its units.`nDo not output commands unless specifically requested."
        $catalog = Get-OpsOllamaModelCatalog -Endpoint $script:OpsDefaultAIEndpoint
        $resolvedModel = Resolve-OpsAIModel -PreferredModel $Model -AvailableModels $catalog.Models
        $payload = @{ model = $resolvedModel; prompt = "$contract`n`n$($ctx.Text)`n`nUser question:`n$Instruction`n`nPowerShell pipeline data:`n$stringifiedData"; stream = $true } | ConvertTo-Json -Depth 5
        $success = $false; $lastErr = $null
        $aiProgressId = Get-Random -Minimum 1 -Maximum 9999
        for ($attempt = 1; $attempt -le (1 + $MaxRetries) -and -not $success; $attempt++) {
            if ($attempt -gt 1) { Write-OpsHeader "  [Retry] $attempt / $((1 + $MaxRetries))..." Yellow; Start-Sleep -Seconds 3 }
            $esc = [char]27
            $reset = "${esc}[0m"
            Write-Host "`n  ${esc}[48;5;183m${esc}[38;5;16m AI ${reset} [${esc}[38;5;183m$($resolvedModel.ToUpper())${reset}] " -NoNewline
            Write-Progress -Id $aiProgressId -Activity "AI Query ($resolvedModel)" -Status "Generating response..." -PercentComplete 50
            $client = [System.Net.Http.HttpClient]::new()
            try {
                $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
                $body = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/json')
                $response = $client.PostAsync("$script:OpsDefaultAIEndpoint/api/generate", $body).GetAwaiter().GetResult()
                $response.EnsureSuccessStatusCode() | Out-Null
                $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult(); $reader = [System.IO.StreamReader]::new($stream)
                $respText = [System.Text.StringBuilder]::new()
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine(); if (-not $line) { continue }
                    try {
                        $chunk = $line | ConvertFrom-Json -ErrorAction Stop
                        if ($chunk.response) { $null = $respText.Append($chunk.response); Write-Host $chunk.response -NoNewline -ForegroundColor White }
                        if ($chunk.done) { break }
                    } catch { Write-Verbose "AI stream chunk parse warning: $($_.Exception.Message)" }
                }
                Write-Host ''; if ($Remember -and $respText.Length -gt 0) { Add-OpsMemory -Text "Question: $Instruction`n`nAnswer: $($respText.ToString())" -Type session -Tag @('ai', $ctx.Intent.ToLowerInvariant()) -Source 'ai' | Out-Null }
                Write-Progress -Id $aiProgressId -Activity "AI Query ($resolvedModel)" -Completed
                $success = $true
            } catch { $lastErr = $_; Write-Warning "AI pipeline failure: $($_.Exception.Message)" } finally { if ($reader) {$reader.Dispose()}; $client.Dispose() }
        }
        if (-not $success -and $lastErr) { throw $lastErr }
    }
}

