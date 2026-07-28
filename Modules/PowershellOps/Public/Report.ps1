# ── PUBLIC: REPORT & DASHBOARD ─────────────────────────────────────────────

function ConvertTo-OpsMarkdownTable {
    <#
    .SYNOPSIS
        Converts an array of objects into a formatted Markdown table with auto-sized columns.
    .OUTPUTS
        [string] A single Markdown table string with header, separator, and data rows.
    #>
    [CmdletBinding()]
    param([object[]]$InputObject, [string]$Section = '')
    $rows = @($InputObject | Where-Object { $null -ne $_ }); if (-not $rows) { return '_No transactional metrics encountered._' }
    $props = @($rows[0].PSObject.Properties.Name)
    $widths = @{ Endpoint = 32; Model = 64; Modified = 20; ProcessName = 28; Company = 28; Name = 42; Target = 76; Source = 48; TaskPath = 34; TaskName = 52; Path = 72; Args = 72; Status = 56; MatchedRule = 32; LastCommit = 56 }
    if ($Section -eq 'Startup') { $widths.Name = 38; $widths.Target = 72; $widths.Source = 44 }
    $fRows = foreach ($r in $rows) {
        $ordered = [ordered]@{}; foreach ($p in $props) { $ordered[$p] = Format-OpsMarkdownCell -Text ([string]$r.PSObject.Properties[$p].Value) -MaxWidth ($widths.ContainsKey($p) ? [int]$widths[$p] : 0) }
        [PSCustomObject]$ordered
    }
    $colWidths = [ordered]@{}; foreach ($p in $props) { $max = $p.Length; foreach ($fr in $fRows) { $len = ([string]$fr.PSObject.Properties[$p].Value).Length; if($len -gt $max){$max = $len} }; $colWidths[$p] = [Math]::Max(3, $max) }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('| ' + (($props | ForEach-Object { $_.PadRight($colWidths[$_]) }) -join ' | ') + ' |')
    $lines.Add('| ' + (($props | ForEach-Object { '-' * $colWidths[$_] }) -join ' | ') + ' |')
    foreach ($fr in $fRows) { $lines.Add('| ' + (($props | ForEach-Object { ([string]$fr.PSObject.Properties[$_].Value).PadRight($colWidths[$_]) }) -join ' | ') + ' |') }
    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-OpsReportMarkdown {
    <#
    .SYNOPSIS
        Converts a full report hashtable into a Markdown document with sections.
    .OUTPUTS
        [string] A complete Markdown document string with a heading and one section per report key.
    #>
    [CmdletBinding()]
    param($Report)
    $lines = [System.Collections.Generic.List[string]]::new(); $lines.Add('# PowershellOps Hybrid Structural Triage Report'); $lines.Add("Generated: $($Report.Generated)`n")
    foreach ($section in @('AI', 'Disk', 'Resources', 'Ports', 'FirewallGaps', 'Startup', 'ScheduledTaskRisks', 'EventStorms')) {
        $lines.Add("## $section`n"); $lines.Add((ConvertTo-OpsMarkdownTable -InputObject $Report[$section] -Section $section))
    }
    return ($lines -join [Environment]::NewLine)
}

function Write-OpsReportTable {
    <#
    .SYNOPSIS
        Renders a formatted console table with ANSI-colored headers and cells.
    .OUTPUTS
        None. Writes formatted output directly to the host console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', 'Intentional console table rendering')]
    [CmdletBinding()]
    param([string]$Title, [hashtable[]]$Columns, [object[]]$InputObject = @(), [string]$Icon = '•', [string]$AnsiColor = '153', [int]$MaxRows = 0)
    $rows = @($InputObject | Where-Object { $null -ne $_ }); $vRows = if ($MaxRows -gt 0) { @($rows | Select-Object -First $MaxRows) } else { $rows }
    $w = (($Columns | ForEach-Object { [int]$_.Width } | Measure-Object -Sum).Sum + (($Columns.Count - 1) * 2))
    $esc = [char]27
    $reset = "${esc}[0m"
    Write-Host "`n  ${esc}[48;5;$AnsiColor;38;5;16m $Icon $Title ${reset}"
    Write-Host "  ${esc}[38;5;246m$('─' * [Math]::Max(1, $w))${reset}"
    if (-not $rows) { Write-Host "  ${esc}[38;5;158m✓ Evaluation parameters stable. No actionable telemetry.${reset}"; return }
    Write-Host ('  ' + (($Columns | ForEach-Object { $hdr = if ($_.Label) { $_.Label } else { $_.Name }; Format-OpsReportCell -Text ($hdr) -Width ([int]$_.Width) }) -join '  ')) -ForegroundColor DarkGray
    foreach ($r in $vRows) {
        Write-Host ('  ' + (($Columns | ForEach-Object {
            $val = if ($_.Expression) { & $_.Expression $r } else { $r.PSObject.Properties[$_.Name].Value }
            Format-OpsReportCell -Text ([string]$val) -Width ([int]$_.Width)
        }) -join '  ')) -ForegroundColor White
    }
}

function New-OpsReport {
    <#
    .SYNOPSIS
        Generates a full system report in Console, Markdown, or JSON format.
    .OUTPUTS
        [string] The report content when Format is Markdown or Json; otherwise writes to a file and renders tables to the console.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)] param([ValidateSet('Console', 'Markdown', 'Json')][string]$Format = 'Console', [string]$Path)
    $prev = $script:OpsSuppressHeaders; $script:OpsSuppressHeaders = $true
    try {
        $report = [ordered]@{
            Generated          = Get-Date
            AI                 = @(Get-OpsAIStatus)
            Disk               = @(Get-OpsDiskPressureAudit)
            Resources          = @(Get-OpsResourceMap)
            Ports              = @(Get-OpsPortMap)
            FirewallGaps       = @(Get-OpsFirewallAudit)
            Startup            = @(Get-OpsBootMap)
            ScheduledTaskRisks = @(Get-OpsScheduledTaskRiskAudit)
            EventStorms        = @(Get-OpsEventStormAudit)
        }
    } finally { $script:OpsSuppressHeaders = $prev }
    $md = ConvertTo-OpsReportMarkdown -Report $report
    if ($Format -eq 'Console') {
        $outPath = if ($Path) { $Path } else { Get-OpsReportPath -Ext md }
        if ($PSCmdlet.ShouldProcess("Report file: $outPath", 'Save report')) {
            Set-Content -Path $outPath -Value $md -Encoding UTF8
        }

        # Pastel Colors: AI=183(Lavender), Sys=158(Mint), Sec=217(Coral), Net=153(Sky), Run=230(Champagne)
        Write-OpsReportTable -Title 'AI Engine Node Status' -Icon '🤖' -AnsiColor '183' -InputObject $report.AI -Columns @(@{Name='Endpoint';Width=20},@{Name='Status';Width=12},@{Name='Model';Width=20})
        Write-OpsReportTable -Title 'System Volume State' -Icon '▰' -AnsiColor '158' -InputObject $report.Disk -Columns @(@{Name='DeviceID';Width=8},@{Name='SizeGB';Width=9},@{Name='FreeGB';Width=9},@{Name='FreePercent';Width=12})
        Write-OpsReportTable -Title 'Active Engine Consumer Workspace' -Icon '▤' -AnsiColor '217' -InputObject $report.Resources -Columns @(@{Name='ProcessName';Width=18},@{Name='Id';Width=7},@{Name='RAMMB';Width=8},@{Name='CPUSec';Width=8})
        Write-OpsReportTable -Title 'Assigned Interface Socket Network Map' -Icon '◦' -AnsiColor '153' -InputObject $report.Ports -Columns @(@{Name='Port';Width=6},@{Name='PID';Width=6},@{Name='Process';Width=18})
        Write-OpsReportTable -Title 'Threat Vector Firewall Gaps' -Icon '▣' -AnsiColor '217' -InputObject $report.FirewallGaps -Columns @(@{Name='Port';Width=6},@{Name='PID';Width=6},@{Name='Process';Width=18},@{Name='Status';Width=40})
        Write-OpsReportTable -Title 'Platform Persistence Startup Hooks' -Icon '⌂' -AnsiColor '158' -InputObject $report.Startup -Columns @(@{Name='Hive';Width=6},@{Name='Name';Width=15},@{Name='Target';Width=45})
        Write-OpsReportTable -Title 'Automated Execution Risk Vectors' -Icon '⌁' -AnsiColor '217' -InputObject $report.ScheduledTaskRisks -Columns @(@{Name='TaskName';Width=20},@{Name='Path';Width=30})
        Write-OpsReportTable -Title 'System Log Notification Storm Events' -Icon '↯' -AnsiColor '217' -InputObject $report.EventStorms -Columns @(@{Name='Count';Width=6},@{Name='Name';Width=6},@{Name='Source';Width=20})
        return
    }
    $output = if ($Format -eq 'Json') { $report | ConvertTo-Json -Depth 8 } else { $md }
    if ($Path) { if ($PSCmdlet.ShouldProcess("Report file: $Path", 'Save report')) { Set-Content -Path $Path -Value $output -Encoding UTF8 } } else { $output }
}

function Show-OpsDashboard {
    <#
    .SYNOPSIS
        Renders the interactive terminal dashboard with category grids and alias references.
    .OUTPUTS
        None. Draws the full dashboard layout to the host console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional user-facing config')]
    [CmdletBinding()]
    param()
    $esc = [char]27
    $reset = "${esc}[0m"
    $aiStatus = try { $null = Invoke-RestMethod -Uri "$script:OpsDefaultAIEndpoint/api/tags" -TimeoutSec 2 -ErrorAction Stop; 'ACTIVE' } catch { 'OFFLINE' }
    $pRoot = $global:OpsProjectRoot ?? $script:OpsDefaultProjectRoot
    $cWidth = try { [Console]::WindowWidth } catch { 120 }
    if ($cWidth -lt 100) { $cWidth = 100 }

    $isNerd = Test-OpsNerdFont

    # Soft Pastel Palette (256-color ANSI)
    $c = @{
        Core   = "158" # Mint
        Vers   = "246" # Soft Gray
        AI     = "153" # Sky Blue
        Sys    = "158" # Mint
        Sec    = "217" # Soft Coral
        Net    = "153" # Sky Blue
        Aim    = "183" # Lavender
        Run    = "230" # Champagne
        Env    = "158" # Mint
        Cfg    = "246" # Gray
        Bord   = "242" # Border Gray
    }

    $categories = @(
        @{ Icon = '󰒓'; Name = 'SYSTEM';      Bg = $c.Sys; Cmds = @('corehealth','sysspec','sysuptime','ramstats','battstatus','gpuview','powertriage','vmcheck','liccheck','diskpressure','tempcheck','clipcheck','smartstatus','resourcemap','portmap','sysdiag') }
        @{ Icon = '󰒕'; Name = 'SECURITY';    Bg = $c.Sec; Cmds = @('adminaudit','shieldstatus','fwcheck','bootmap','taskrisk','ghostports','susprocs','eventstorm','certaudit','dumpmap','filecheck','shortcutcheck','lockcheck','sparsecheck','compresscheck','patchhistory','driveraudit','recentfiles','secretmask','auditdiag') }
        @{ Icon = '󰒢'; Name = 'NETWORK';     Bg = $c.Net; Cmds = @('netping','wificheck','peerscheck','dnsbench','netspeed','smbshares','hostscheck','dnsmap','nettriage','netview') }
        @{ Icon = '󰒙'; Name = 'AI/MEM';      Bg = $c.Aim; Cmds = @('ask','fix','hub','brief','websearch','mem','airecall','aistatus','aiintent','aiprofile','memorymap','memoryfile') }
        @{ Icon = '󰒖'; Name = 'RUN';         Bg = $c.Run; Cmds = @('stat','dailycheck','sysreview','secaudit','netreview','threathunt','changeaudit','compliancecheck','fullreport') }
        @{ Icon = '󰆧'; Name = 'ENVIRONMENT'; Bg = $c.Env; Cmds = @('envmap','pathaudit','applist','apploc','envdiag') }
        @{ Icon = '󰅟'; Name = 'CORE';        Bg = $c.Cfg; Cmds = @('projview','projset','openhere','cached','corecache','opsonboard','coreindex','watchindex','corereload','coreinit','coremanual') }
    )

    $headerWidth = 18
    $colWidth = 16
    $maxLineCmds = [Math]::Floor(($cWidth - $headerWidth - 10) / $colWidth)
    if ($maxLineCmds -lt 1) { $maxLineCmds = 1 }
    $boxWidth = 25 + ($maxLineCmds * $colWidth)

    # 1. TOP FRAME
    Write-Host "`n  ${esc}[38;5;$($c.Bord)m┌$($('─' * ($boxWidth - 2)))┐${reset}"

    # 2. BRANDING HEADER
    $brandText = " Ops : CORE "
    $verText   = " v$script:OpsVersion "
    $aiText    = " AI: $aiStatus "
    Write-Host "  ${esc}[38;5;$($c.Bord)m│${reset} " -NoNewline
    Write-Host "${esc}[48;5;$($c.Core);38;5;16m$brandText${reset} " -NoNewline
    Write-Host "${esc}[38;5;$($c.Vers)m$verText${reset} " -NoNewline
    Write-Host "${esc}[38;5;$($c.AI)m$aiText${reset}" -NoNewline
    $headerLen = $brandText.Length + $verText.Length + $aiText.Length + 4
    Write-Host (" " * ($boxWidth - $headerLen - 2)) -NoNewline
    Write-Host "${esc}[38;5;$($c.Bord)m│${reset}"

    Write-Host "  ${esc}[38;5;$($c.Bord)m├$($('─' * ($headerWidth + 2)))┬$($('─' * ($boxWidth - $headerWidth - 5)))┤${reset}"

    # 3. CATEGORIES & GRIDS
    foreach ($cat in $categories) {
        $icon = if ($isNerd) { $cat.Icon } else { '•' }
        $label = "$icon $($cat.Name)".Trim()

        $lineCmds = 0
        $firstLine = $true

        for ($i = 0; $i -lt $cat.Cmds.Count; $i++) {
            if ($lineCmds -eq 0) {
                if (-not $firstLine) {
                    Write-Host (" " * ($boxWidth - ($maxLineCmds * $colWidth) - $headerWidth - 5)) -NoNewline
                    Write-Host "${esc}[38;5;$($c.Bord)m│${reset}"
                }
                Write-Host "  ${esc}[38;5;$($c.Bord)m│${reset} " -NoNewline
                if ($firstLine) {
                    Write-Host "${esc}[38;5;$($cat.Bg)m$($label.PadRight($headerWidth))${reset} ${esc}[38;5;$($c.Bord)m│${reset} " -NoNewline
                } else {
                    Write-Host (" " * $headerWidth) -NoNewline
                    Write-Host " ${esc}[38;5;$($c.Bord)m│${reset} " -NoNewline
                }
                $firstLine = $false
            }

            Write-Host ($cat.Cmds[$i].PadRight($colWidth)) -NoNewline -ForegroundColor White
            $lineCmds++

            if ($lineCmds -eq $maxLineCmds) {
                $lineCmds = 0
            }
        }

        # Padding for the last line of a category
        if ($lineCmds -gt 0) {
            Write-Host (" " * (($maxLineCmds - $lineCmds) * $colWidth)) -NoNewline
        }
        Write-Host (" " * ($boxWidth - ($maxLineCmds * $colWidth) - $headerWidth - 5)) -NoNewline
        Write-Host "${esc}[38;5;$($c.Bord)m│${reset}"

        if ($cat.Name -ne 'CORE') {
            Write-Host "  ${esc}[38;5;$($c.Bord)m├$($('─' * ($headerWidth + 2)))┼$($('─' * ($boxWidth - $headerWidth - 5)))┤${reset}"
        }
    }

    # 4. FOOTER FRAME
    Write-Host "  ${esc}[38;5;$($c.Bord)m├$($('─' * ($boxWidth - 2)))┤${reset}"
    $envLabel = " ENV: $pRoot "
    Write-Host "  ${esc}[38;5;$($c.Bord)m│${reset} " -NoNewline
    Write-Host $envLabel.PadRight($boxWidth - 4) -ForegroundColor DarkGray -NoNewline
    Write-Host " ${esc}[38;5;$($c.Bord)m│${reset}"
    Write-Host "  ${esc}[38;5;$($c.Bord)m└$($('─' * ($boxWidth - 2)))┘${reset}"
}

function Watch-OpsDashboard {
    <#
    .SYNOPSIS
        Continuously refreshes the dashboard at a specified interval.
    .OUTPUTS
        None. Redraws the dashboard in a loop until interrupted.
    #>
    [CmdletBinding()]
    param([int]$IntervalSeconds = 2)
    if (-not (Test-OpsInteractiveSession)) { Write-Warning "Dashboard requires an interactive terminal session."; return }
    Write-Information "  [Watch] Dashboard live refresh every ${IntervalSeconds}s. Press Ctrl+C to exit." -InformationAction Continue
    while ($true) { Clear-Host; Show-OpsDashboard; Start-Sleep -Seconds $IntervalSeconds }
}
