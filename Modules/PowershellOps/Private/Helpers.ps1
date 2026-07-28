# ── PRIVATE HELPERS ──────────────────────────────────────────────────────────

# ── 1. CENTRALIZED PLATFORM DATA CACHE SUITE ──────────────────────────────
function Get-OpsCacheSnapshot {
    [CmdletBinding()]
    param()

    $entries = @(
        foreach ($key in @($script:OpsCacheStore.Keys | Sort-Object)) {
            $entry = $script:OpsCacheStore[$key]
            if ($null -eq $entry) { continue }

            [PSCustomObject]@{
                Key        = $key
                CachedAt   = $entry.Timestamp
                AgeSeconds = if ($entry.Timestamp) {
                    [Math]::Round(((Get-Date) - $entry.Timestamp).TotalSeconds, 2)
                } else {
                    $null
                }
                ValueType  = if ($null -ne $entry.Value) { $entry.Value.GetType().Name } else { '' }
            }
        }
    )

    if (-not $entries) { return @() }
    $entries
}

function Invoke-OpsCachedData {
    [CmdletBinding()]
    param(
        [string]$Key,
        [int]$ExpirySeconds,
        [scriptblock]$ScriptBlock
    )

    if (-not $PSBoundParameters.Count) {
        return Get-OpsCacheSnapshot
    }

    if ([string]::IsNullOrWhiteSpace($Key) -or $ExpirySeconds -lt 0 -or -not $ScriptBlock) {
        throw 'Invoke-OpsCachedData requires -Key, -ExpirySeconds, and -ScriptBlock unless called without parameters to inspect the cache.'
    }

    $now = Get-Date

    if ($script:OpsCacheStore.ContainsKey($Key)) {
        $entry = $script:OpsCacheStore[$Key]
        if (($now - $entry.Timestamp).TotalSeconds -lt $ExpirySeconds) {
            return $entry.Value
        }
    }

    $computedValue = &$ScriptBlock
    $script:OpsCacheStore[$Key] = [hashtable]::Synchronized(@{ Timestamp = $now; Value = $computedValue })
    return $computedValue
}

# ── 2. TYPED ARCHITECTURE CORE MEMORY SCHEMA ─────────────────────────────────────
class OpsMemoryEntry {
    [string] $Id
    [string] $Type
    [string[]]$Tags
    [string] $Text
    [string] $Source
    [string] $Created
    [string] $Confidence
    [bool]   $Pinned
    [float[]]$Embedding
    [string] $Path

    OpsMemoryEntry() {}

    OpsMemoryEntry([hashtable]$map) {
        $this.Id         = $map.Id
        $this.Type       = $map.Type
        $this.Tags       = $map.Tags
        $this.Text       = $map.Text
        $this.Source     = $map.Source
        $this.Created    = $map.Created
        $this.Confidence = $map.Confidence
        $this.Pinned     = [bool]$map.Pinned
        if ($map.Embedding) { $this.Embedding = [float[]]$map.Embedding }
        if ($map.Path) { $this.Path = $map.Path }
    }
}

# ── 3. BASELINE ENVIRONMENT LOGIC ────────────────────────────────────────────────
function Write-OpsHeader {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Accept parameter for API consistency')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ConsoleColor]$Color = 'Cyan'
    )
    if (-not $script:OpsSuppressHeaders) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Test-OpsInteractiveSession {
    if ($env:Ops_NO_DASH -or $env:CI) { return $false }
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsOutputRedirected
    } catch {
        return $false
    }
}

function Test-OpsNerdFont {
    [CmdletBinding()]
    param()
    # Attempt to render a high-plane unicode character and check if it's potentially supported
    # This is a heuristic: we check if the console font name contains 'Nerd' (modern terminals only)
    # or if we are in Windows Terminal which usually has it.
    if ($env:WT_SESSION) { return $true }
    try {
        $font = (Get-ItemProperty "HKCU:\Console" -ErrorAction SilentlyContinue).FaceName
        if ($font -match 'Nerd') { return $true }
    } catch {}
    return $false
}

function Test-OpsModulePublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName
    )

    $policy = $script:OpsTrustedModulePublishers[$ModuleName]
    if (-not $policy) {
        return [PSCustomObject]@{
            Module          = $ModuleName
            Trusted         = $true
            Status          = 'NoPolicy'
            Author          = ''
            CompanyName     = ''
            ExpectedAuthor  = ''
            ExpectedCompany = ''
            Message         = ''
        }
    }

    $module = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        return [PSCustomObject]@{
            Module          = $ModuleName
            Trusted         = $false
            Status          = 'Missing'
            Author          = ''
            CompanyName     = ''
            ExpectedAuthor  = $policy.Author
            ExpectedCompany = $policy.CompanyName
            Message         = 'Module is not installed.'
        }
    }

    $manifestPath = Join-Path $module.ModuleBase ($ModuleName + '.psd1')
    if (-not (Test-Path $manifestPath)) {
        return [PSCustomObject]@{
            Module          = $ModuleName
            Trusted         = $false
            Status          = 'Unverified'
            Author          = ''
            CompanyName     = ''
            ExpectedAuthor  = $policy.Author
            ExpectedCompany = $policy.CompanyName
            Message         = "Module manifest not found at $manifestPath."
        }
    }

    try {
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        $authorOk = $manifest.Author -eq $policy.Author
        $companyOk = $null -eq $policy.CompanyName -or @($manifest.CompanyName) -contains $policy.CompanyName
        $trusted = $authorOk -and $companyOk

        return [PSCustomObject]@{
            Module          = $ModuleName
            Trusted         = $trusted
            Status          = if ($trusted) { 'Trusted' } else { 'Untrusted' }
            Author          = $manifest.Author
            CompanyName     = $manifest.CompanyName
            ExpectedAuthor  = $policy.Author
            ExpectedCompany = $policy.CompanyName
            Message         = if ($trusted) { '' } else { 'Installed module metadata did not match the expected publisher profile.' }
        }
    } catch {
        return [PSCustomObject]@{
            Module          = $ModuleName
            Trusted         = $false
            Status          = 'VerificationFailed'
            Author          = ''
            CompanyName     = ''
            ExpectedAuthor  = $policy.Author
            ExpectedCompany = $policy.CompanyName
            Message         = $_.Exception.Message
        }
    }
}

function Get-OpsSafeAliasName {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -match '^(?i)Ops-') { return $Name }
    return "Ops-$Name"
}

function Get-OpsConfigurationPath {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:OpsConfigRoot)) {
        $null = New-Item -Path $script:OpsConfigRoot -ItemType Directory -Force
    }
    $script:OpsConfigFile
}

function Read-OpsConfiguration {
    [CmdletBinding()]
    param()
    $config = [ordered]@{
        ProjectRoot     = $script:OpsDefaultProjectRoot
        MemoryRoot      = $script:OpsMemoryRoot
        AIEndpoint      = $script:OpsDefaultAIEndpoint
        AIModel         = $script:OpsDefaultAIModel
        ModelFile       = $script:OpsAIModelFile
        SetupCompleted  = $false
        LastUpdated     = $null
    }

    $path = Get-OpsConfigurationPath
    if (Test-Path $path) {
        try {
            $loaded = Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            foreach ($key in $loaded.Keys) {
                if ($null -ne $loaded[$key] -and $loaded[$key] -ne '') {
                    $config[$key] = $loaded[$key]
                }
            }
        } catch {
            Write-Verbose "Configuration read skipped: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]$config
}

function Write-OpsConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Configuration
    )
    $path = Get-OpsConfigurationPath
    $payload = [ordered]@{
        ProjectRoot    = $Configuration.ProjectRoot
        MemoryRoot     = $Configuration.MemoryRoot
        AIEndpoint     = $Configuration.AIEndpoint
        AIModel        = $Configuration.AIModel
        ModelFile      = $Configuration.ModelFile
        SetupCompleted = [bool]$Configuration.SetupCompleted
        LastUpdated    = (Get-Date).ToString('o')
    }

    if ($PSCmdlet.ShouldProcess($path, 'Save onboarding configuration')) {
        $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
    }

    [PSCustomObject]$payload
}

function Import-OpsConfiguration {
    [CmdletBinding()]
    param()
    $config = Read-OpsConfiguration

    if ($config.ProjectRoot) { $script:OpsDefaultProjectRoot = $config.ProjectRoot }
    if ($config.MemoryRoot) {
        $script:OpsMemoryRoot = $config.MemoryRoot
        $script:OpsMemoryFile = Join-Path $script:OpsMemoryRoot 'ops-memory.jsonl'
    }
    if ($config.AIEndpoint) { $script:OpsDefaultAIEndpoint = $config.AIEndpoint }
    if ($config.AIModel) { $script:OpsDefaultAIModel = $config.AIModel }
    if ($config.ModelFile) { $script:OpsAIModelFile = $config.ModelFile }

    $config
}

function Get-OpsOllamaModelCatalog {
    [CmdletBinding()]
    param([string]$Endpoint = $script:OpsDefaultAIEndpoint)

    $items = [System.Collections.Generic.List[object]]::new()
    $source = 'Unavailable'
    $message = ''

    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        try {
            $lines = @(& ollama list 2>$null)
            foreach ($line in $lines) {
                if ($line -match '^\s*(?<Name>\S+)\s+(?<Id>\S+)\s+(?<Size>\S+)\s+(?<Modified>.+)$') {
                    if ($matches.Name -notin @('NAME', 'REPOSITORY')) {
                        $items.Add([PSCustomObject]@{
                            Name     = $matches.Name
                            Size     = $matches.Size
                            Modified = $matches.Modified.Trim()
                            Source   = 'ollama list'
                        })
                    }
                }
            }
            if ($items.Count -gt 0) { $source = 'ollama list' }
        } catch {
            $message = $_.Exception.Message
        }
    }

    if ($items.Count -eq 0) {
        try {
            $response = Invoke-RestMethod -Uri "$Endpoint/api/tags" -TimeoutSec 5 -ErrorAction Stop
            foreach ($model in @($response.models)) {
                $items.Add([PSCustomObject]@{
                    Name     = $model.name
                    Size     = if ($model.size) { [Math]::Round($model.size / 1GB, 2) } else { $null }
                    Modified = $model.modified_at
                    Source   = 'api/tags'
                })
            }
            if ($items.Count -gt 0) { $source = 'api/tags' }
        } catch {
            if (-not $message) { $message = $_.Exception.Message }
        }
    }

    [PSCustomObject]@{
        Endpoint = $Endpoint
        Source   = $source
        Message  = $message
        Models   = @($items)
    }
}

function Resolve-OpsAIModel {
    [CmdletBinding()]
    param(
        [string]$PreferredModel,
        [object[]]$AvailableModels = @()
    )

    $names = @($AvailableModels | ForEach-Object { $_.Name } | Where-Object { $_ })
    if ($PreferredModel -and $names -contains $PreferredModel) { return $PreferredModel }
    if ($script:OpsDefaultAIModel -and $names -contains $script:OpsDefaultAIModel) { return $script:OpsDefaultAIModel }
    if ($names.Count -gt 0) { return $names[0] }
    if ($PreferredModel) { return $PreferredModel }
    return $script:OpsDefaultAIModel
}

function Format-OpsMemoryId {
    param()
    "mem_{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 6))
}

function Get-OpsMemorySearchTerm {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $stopWords = @('the','and','for','with','that','this','from','into','what','when','where','which','how','why','are','you','your','about','using','use')
    [regex]::Matches($Text.ToLowerInvariant(), '[a-z0-9][a-z0-9._-]{2,}') | ForEach-Object { $_.Value } | Where-Object { $_ -notin $stopWords } | Select-Object -Unique -First 18
}

function Format-OpsMemorySnippet {
    param([AllowNull()][string]$Text, [int]$MaxLength = 220)
    if ($null -eq $Text) { return '' }
    $clean = (($Text -replace "(`r`n|`n|`r)", ' ') -replace '\s+', ' ').Trim()
    if ($clean.Length -le $MaxLength) { return $clean }
    return $clean.Substring(0, $MaxLength - 1) + '…'
}

function Format-OpsMarkdownCell {
    param([AllowNull()][string]$Text, [int]$MaxWidth = 0)
    if ($null -eq $Text) { $Text = '' }
    $clean = ($Text -replace "(`r`n|`n|`r)", ' ') -replace '\s+', ' '
    $clean = $clean.Trim().Replace('|', '\|')
    if ($MaxWidth -gt 0 -and $clean.Length -gt $MaxWidth) { return $clean.Substring(0, $MaxWidth - 1) + '…' }
    return $clean
}

function Format-OpsReportCell {
    param([AllowNull()][string]$Text, [int]$Width)
    if ($Width -le 0) { return '' }; if ($null -eq $Text) { $Text = '' }
    $clean = (($Text -replace "(`r`n|`n|`r)", ' ') -replace '\s+', ' ').Trim()
    if ($clean.Length -gt $Width) { return $clean.Substring(0, $Width - 1) + '…' }
    return $clean.PadRight($Width)
}

function Get-OpsReportPath {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', 'Internal helper called from New-OpsReport which has ShouldProcess')]
    param([string]$Ext = 'md')
    if (-not (Test-Path $script:OpsReportRoot)) { $null = New-Item -Path $script:OpsReportRoot -ItemType Directory -Force }
    return Join-Path $script:OpsReportRoot ("Opsreport-{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Ext)
}

function Get-OpsCapabilitiesMap {
    <#
    .SYNOPSIS
    Returns a static map of core aliases and their high-level functionality for AI context.
    #>
    return @"
Available PowershellOps Tools:
- brief: Daily executive report (Top news + System Health + Security Verdict).
- fix: AI-driven terminal error remediation (analyzes last error).
- hub: Central companion dispatcher for all AI/research tasks.
- ask <query>: All-purpose pipable research and analysis tool.
- stat: Instant workstation health snapshot (CPU, RAM, Disk, Temp).
- mem <note>: Save personal operational notes/preferences to vector memory.
- web <query>: Deep online research across multiple search engines.
- scan: AI-driven security audit and threat hunt.
- proj: View or set the current active project root.
- secaudit: Full security compliance and firewall audit.
- netreview: Network diagnostics and link speed triage.
"@
}

