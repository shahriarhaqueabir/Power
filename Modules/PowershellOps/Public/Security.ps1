# ── PUBLIC: SECURITY AUDIT ────────────────────────────────────────────────

function Get-OpsFirewallAudit {
    <#
    .SYNOPSIS
    Cross-references listening ports against firewall inbound allow rules.
    .OUTPUTS
    PSCustomObject with Port, PID, Process, and Status.
    #>
    [CmdletBinding()]
    param()
    return Invoke-OpsCachedData -Key 'sys_fwaudit' -ExpirySeconds 60 -ScriptBlock {
        if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ Port = 'ALL'; PID = '0'; Process = 'N/A'; Status = 'NetSecurity Module Missing' }
        }
        $listeners = Get-OpsPortMap
        $allowPorts = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
            Select-Object -First 200 |
            Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
            ForEach-Object { $_.LocalPort } | Where-Object { $_ -match '^\d+$' } | Select-Object -Unique
        $listeners | ForEach-Object {
            $matched = if ($_.Port -in $allowPorts) { 'Allowed' } else { 'NO_MATCHING_INBOUND_ALLOW_RULE' }
            [PSCustomObject]@{
                Port    = $_.Port
                PID     = $_.PID
                Process = $_.Process
                Status  = $matched
            }
        }
    }
}

function Get-OpsBootMap {
    <#
    .SYNOPSIS
    Lists registry Run keys for startup persistence entries.
    .OUTPUTS
    PSCustomObject with Hive, Name, and Target.
    #>
    [CmdletBinding()]
    param()
    return Invoke-OpsCachedData -Key 'sys_bootmap' -ExpirySeconds 300 -ScriptBlock {
        $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $val = Get-ItemProperty -Path $p
                $val.PSObject.Properties |
                    Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') } |
                    ForEach-Object { [PSCustomObject]@{ Hive = (Split-Path $p -Leaf); Name = $_.Name; Target = $_.Value } }
            }
        }
    }
}

function Get-OpsScheduledTaskRiskAudit {
    <#
    .SYNOPSIS
    Lists non-Microsoft scheduled tasks that could indicate persistence.
    .OUTPUTS
    PSCustomObject with TaskName and Path.
    #>
    [CmdletBinding()]
    param()
    return Invoke-OpsCachedData -Key 'sys_taskaudit' -ExpirySeconds 300 -ScriptBlock {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }
        Get-ScheduledTask |
            Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\\\Microsoft' } |
            Select-Object -First 10 |
            ForEach-Object { [PSCustomObject]@{ TaskName = $_.TaskName; Path = $_.TaskPath } }
    }
}

function Get-OpsGhostPortAudit {
    <#
    .SYNOPSIS
    Returns listening ports with unknown or unidentified processes.
    .OUTPUTS
    PSCustomObject with Port, PID, and Process.
    #>
    [CmdletBinding()]
    param()
    Get-OpsPortMap | Where-Object { $_.Process -in @('Unknown', 'System Listen Stack') }
}

function Get-OpsSuspiciousProcessAudit {
    <#
    .SYNOPSIS
    Lists processes running from AppData or Temp directories.
    .OUTPUTS
    PSCustomObject with Name, Id, Path, CPU, and RAMMB.
    #>
    [CmdletBinding()]
    param()
    Get-Process | Where-Object { $_.Path -and $_.Path -match '(?i)(\\AppData\\|\\Temp\\|\\Windows\\Temp\\)' } |
        Select-Object Name, Id, @{N='Path';E={$_.Path}}, @{N='CPU';E={[Math]::Round($_.CPU, 1)}}, @{N='RAMMB';E={[Math]::Round($_.WorkingSet / 1MB, 1)}}
}

function Get-OpsEventStormAudit {
    <#
    .SYNOPSIS
    Detects application log event storms in the last 15 minutes.
    .OUTPUTS
    PSCustomObject with Count, Name, and Source.
    #>
    [CmdletBinding()]
    param()
    return Invoke-OpsCachedData -Key 'sys_eventstorm' -ExpirySeconds 20 -ScriptBlock {
        try {
            $cutoff = (Get-Date).AddMinutes(-15)
            Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $cutoff } -MaxEvents 200 -ErrorAction SilentlyContinue |
                Group-Object ProviderName |
                Sort-Object Count -Descending |
                Select-Object -First 5 |
                ForEach-Object { [PSCustomObject]@{ Count = $_.Count; Name = $_.Name; Source = 'Application Log' } }
        } catch { return @() }
    }
}

function Get-OpsShield {
    <#
    .SYNOPSIS
    Returns Windows Defender antivirus and real-time protection status.
    .OUTPUTS
    PSCustomObject with Defender status fields.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Status = 'Defender cmdlets unavailable' }
    }
    Get-MpComputerStatus -ErrorAction SilentlyContinue |
        Select-Object AntivirusEnabled, RealTimeProtectionEnabled, LastQuickScanTime, AMServiceEnabled,
            @{N='LastQuickScanResult';E={$_.LastQuickScanResult -join ';'}}
}

function Get-OpsEnvMap {
    <#
    .SYNOPSIS
    Returns all environment variables.
    .OUTPUTS
    PSCustomObject with Name and Value.
    #>
    [CmdletBinding()]
    param()
    Get-ChildItem Env: | Select-Object Name, Value
}

function Get-OpsPathAudit {
    <#
    .SYNOPSIS
    Validates each PATH directory for existence.
    .OUTPUTS
    PSCustomObject with Path and Exists.
    #>
    [CmdletBinding()]
    param()
    $env:Path -split ';' | ForEach-Object { [PSCustomObject]@{ Path = $_; Exists = (Test-Path $_) } }
}

function Protect-OpsSensitiveText {
    <#
    .SYNOPSIS
    Redacts sensitive key-value pairs in text using pattern matching.
    .OUTPUTS
    String with sensitive values replaced by <REDACTED>.
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][AllowNull()]$InputObject)
    process {
        if ($null -eq $InputObject) { return }
        $text = if ($InputObject -is [string]) { $InputObject } else { $InputObject | Out-String }

        $cleanPattern = $script:OpsSensitiveNamePattern -replace '\(\?[a-z]+\)', ''
        $redacted = [regex]::Replace($text, ('(?im)^(\s*[^=\r\n]*(?:' + $cleanPattern + ')[^=\r\n]*\s*=\s*).+$'), '$1<REDACTED>')
        $jsonPattern = '(?i)("(?:[^"]*(?:' + $cleanPattern + ')[^"]*)"\s*:\s*")[^"]*(")'
        [regex]::Replace($redacted, $jsonPattern, '$1<REDACTED>$2')
    }
}

function Test-OpsPromptInjection {
    <#
    .SYNOPSIS
    Scores text for prompt injection risk using pattern matching and optional AI heuristic.
    .OUTPUTS
    Boolean indicating whether the text is suspected injection.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Payload,
        [switch]$UseAIHeuristic,
        [int]$MaxContentLength = 51200
    )
    if ([string]::IsNullOrWhiteSpace($Payload)) { return $false }
    if ($Payload.Length -gt $MaxContentLength) {
        Write-Verbose 'PromptInjection: Payload exceeds max content length threshold'
        return $true
    }

    $score = 0

    $dangerousPatterns = @(
        '(?i)\bignore\s+(?:(?:previous|above|all)\s+)*instructions\b',
        '(?i)\byou\s+are\s+now\b',
        '(?i)\bsystem\s*prompt\b',
        '(?i)\bDAN\b',
        '(?i)\bdo\s+not\s+output\b',
        '(?i)\bforget\s+(?:all\s+)?(?:previous|above)\s+instructions\b',
        '(?i)\bnew\s+instructions?\s*:\s*ignore\b',
        '(?i)\boverride\s+(?:all\s+)?(?:previous|above\s+)?instructions\b',
        '(?i)\boutput\s+(?:only|just|exactly)\b'
    )
    foreach ($pat in $dangerousPatterns) {
        if ($Payload -match $pat) { $score += 25 }
    }

    $hasBase64 = $Payload -match '(?i)(?:[A-Za-z0-9+/]{40,}={0,2})' -or $Payload -match '(?i)(?:[A-Za-z0-9_-]{40,})'
    $hasHex = $Payload -match '(?i)(?:0x[0-9A-Fa-f]{8,}|\\x[0-9A-Fa-f]{2})'
    $hasPercentEncoding = $Payload -match '(?:%[0-9A-Fa-f]{2}){10,}'
    $hasUnicodeEscape = $Payload -match '(?:\\u[0-9A-Fa-f]{4}){3,}'
    $hasRepeatedEncoding = ($Payload -match '(?i)(?:base64|hex\s*encode|rot13|atob|btoa|unescape)')
    if ($hasBase64) { $score += 15 }
    if ($hasHex) { $score += 15 }
    if ($hasPercentEncoding) { $score += 10 }
    if ($hasUnicodeEscape) { $score += 10 }
    if ($hasRepeatedEncoding) { $score += 15 }

    $excessiveNewlines = ([regex]::Matches($Payload, '\n').Count -gt 50)
    $nullTokenInjection = $Payload -match '\x00|\\x00|\\0'
    if ($excessiveNewlines) { $score += 5 }
    if ($nullTokenInjection) { $score += 20 }

    if ($UseAIHeuristic -and $score -ge 10 -and $score -lt 40) {
        try {
            $null = Get-OpsAIStatus -Endpoint $script:OpsDefaultAIEndpoint -ErrorAction SilentlyContinue
        } catch { Write-Verbose 'PromptInjection: Ollama unavailable for AI heuristic, skipping'; return ($score -ge 25) }

        try {
            $probePrompt = "Classify the following text as 'safe' or 'injection' (respond with one word only):`n`n$($Payload.Substring(0, [Math]::Min(500, $Payload.Length)))"
            $aiPayload = @{ model = $script:OpsDefaultAIModel; prompt = $probePrompt; stream = $false } | ConvertTo-Json -Depth 3
            $aiResp = Invoke-RestMethod -Uri "$script:OpsDefaultAIEndpoint/api/generate" -Method Post -Body $aiPayload -ContentType 'application/json' -TimeoutSec 10 -ErrorAction Stop
            if ($aiResp.response -match '(?i)\binjection\b') { $score += 30 }
            Write-Verbose "PromptInjection: AI heuristic returned score adjustment"
        } catch { Write-Verbose 'PromptInjection: AI heuristic unavailable, skipping layer 4' }
    }

    return ($score -ge 25)
}

function Get-OpsSourceQualityScore {
    <#
    .SYNOPSIS
    Returns a quality score (0-100) for scraped web content based on length and domain.
    .OUTPUTS
    Int32 quality score between 0 and 100.
    #>
    [CmdletBinding()]
    param([string]$Url, [AllowNull()][string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return 0 }
    $score = 50
    if ($Content.Length -gt 200)  { $score += 20 }
    if ($Content.Length -gt 800)  { $score += 15 }
    if ($Url -match '\.(gov|edu|org)(/|$)') { $score += 15 }
    return [Math]::Min(100, $score)
}

function Get-OpsAudit {
    <#
    .SYNOPSIS
    Routes to a specific security audit function by type.
    .OUTPUTS
    PSCustomObject results from the selected audit function.
    #>
    [CmdletBinding()]
    param([ValidateSet('Firewall','Boot','ScheduledTask','GhostPort','SuspiciousProcess','EventStorm','Patch','Temp','Clip')][string]$Type = 'Firewall')
    switch ($Type) {
        'Firewall'          { Get-OpsFirewallAudit }
        'Boot'              { Get-OpsBootMap }
        'ScheduledTask'     { Get-OpsScheduledTaskRiskAudit }
        'GhostPort'         { Get-OpsGhostPortAudit }
        'SuspiciousProcess' { Get-OpsSuspiciousProcessAudit }
        'EventStorm'        { Get-OpsEventStormAudit }
        'Patch'             { Get-OpsPatchHistory }
        'Temp'              { Get-OpsTempCheck }
        'Clip'              { Get-OpsClipCheck }
    }
}
