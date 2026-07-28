# ── PUBLIC: HIGH-SPEED SHORTCUTS & COMPANION HUB ─────────────────────────────

function Invoke-OpsShortAsk {
    <#
    .SYNOPSIS
    High-speed AI research shortcut. Pipable and context-aware.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)][object[]]$InputData,
        [Parameter(Position = 0, Mandatory = $true)][string]$Instruction
    )
    begin { $buffer = [System.Collections.Generic.List[object]]::new() }
    process { if ($null -ne $_) { $buffer.Add($_) } }
    end {
        Invoke-OpsAI -InputData $buffer.ToArray() -Instruction $Instruction -FullEnv
    }
}

function Invoke-OpsShortFix {
    <#
    .SYNOPSIS
    Automated error remediation. Uses the SystemAnalyst pattern.
    #>
    [CmdletBinding()]
    param()
    Invoke-OpsCompanion -Mode fix
}

function Invoke-OpsShortStat {
    <#
    .SYNOPSIS
    Lightweight workstation health dashboard.
    #>
    [CmdletBinding()]
    param()
    Invoke-OpsDailyOps | Out-Null
}

function Invoke-OpsShortMem {
    <#
    .SYNOPSIS
    Fast-capture vector memory storage.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0, Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Text)
    Add-OpsMemory -Text $Text -Type note -Source 'shortcut'
}

function Get-OpsDailyBrief {
    <#
    .SYNOPSIS
    All-purpose daily driver: Top News + System Health + Security Alerts.
    #>
    [CmdletBinding()]
    param([int]$Sources = 5)
    Invoke-OpsCompanion -Mode brief -Sources $Sources
}

function Invoke-OpsCompanion {
    <#
    .SYNOPSIS
    The Universal AI Companion Hub. Central brain for research and diagnostics.
    .EXAMPLE
    hub brief
    hub fix
    Get-Process | hub "Which is using most RAM?"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Query,
        [Parameter(ValueFromPipeline = $true)][object]$InputObject,
        [ValidateSet('ask', 'brief', 'fix', 'scan', 'recall')][string]$Mode = 'ask',
        [int]$Sources = 5
    )
    begin {
        $rawQuery = ($Query -join ' ').Trim()
        $pipelineData = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $_) { $pipelineData.Add($_) }
    }
    end {
        # Auto-detect mode if Query matches specific keywords
        if ($Mode -eq 'ask') {
            if ($rawQuery -match '^brief$') { $Mode = 'brief'; $rawQuery = '' }
            elseif ($rawQuery -match '^fix$') { $Mode = 'fix'; $rawQuery = '' }
            elseif ($rawQuery -match '^scan$') { $Mode = 'scan'; $rawQuery = '' }
            elseif ($rawQuery -match '^recall\s+(.*)') { $Mode = 'recall'; $rawQuery = $matches[1].Trim() }
        }

        $dateTime = (Get-Date).ToString('F')
        $lastErr = if ($null -ne $Error -and $Error.Count -gt 0) { $Error[0] } else { "No errors detected." }

        switch ($Mode) {
            'brief' {
                $health = Get-OpsHealth
                $patternPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Patterns\DailyBrief.md'
                $pattern = if (Test-Path $patternPath) { Get-Content $patternPath -Raw } else { "Synthesize news and health: {WebSearchData} | {HealthStatus}" }

                $healthStatus = "CPU: $($health.'CPU Load'), RAM: $($health.'RAM Usage'), Procs: $($health.Processes)"
                $fullPattern = $pattern.Replace('{DateTime}', $dateTime).Replace('{HealthStatus}', $healthStatus).Replace('{LastErrors}', "$lastErr")

                Write-OpsHeader "  [HUB] Generating Daily Briefing..." Magenta
                Invoke-OpsSearch -Query "top news stories today" -AI -Sources $Sources -Instruction $fullPattern
            }

            'fix' {
                $health = Get-OpsHealth
                $patternPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Patterns\SystemAnalyst.md'
                $pattern = if (Test-Path $patternPath) { Get-Content $patternPath -Raw } else { "Fix this error: {LastError}" }

                $healthStatus = "CPU: $($health.'CPU Load'), RAM: $($health.'RAM Usage')"
                $fullPattern = $pattern.Replace('{HealthStatus}', $healthStatus).Replace('{LastError}', "$lastErr").Replace('{Environment}', "PowerShell 7.6 LTS")

                Write-OpsHeader "  [HUB] Analyzing last error for remediation..." Yellow
                Invoke-OpsAI -Instruction $fullPattern
            }

            'scan' {
                Write-OpsHeader "  [HUB] Initiating AI-driven system scan..." Cyan
                $audit = Invoke-OpsSecurityAudit
                $msg = "Analyze these security audit results and provide a 'Security Verdict': `n$($audit | Out-String)"
                Invoke-OpsAI -Instruction $msg -FullEnv
            }

            'recall' {
                Write-OpsHeader "  [HUB] Searching vector memory for '$rawQuery'..." Blue
                Search-OpsMemory -Query $rawQuery
            }

            'ask' {
                if (-not $rawQuery -and $pipelineData.Count -eq 0) {
                    Write-OpsHeader "  [HUB] Ready. Type 'hub brief', 'hub fix', or ask a question." Gray
                    return
                }
                # Leverage FullEnv for ambient context injection
                $data = if ($pipelineData.Count -gt 0) { $pipelineData.ToArray() } else { $null }
                $instr = if ($rawQuery) { $rawQuery } else { "Analyze this data." }
                Invoke-OpsAI -InputData $data -Instruction $instr -FullEnv
            }
        }
    }
}
