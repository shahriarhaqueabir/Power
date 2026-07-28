# ── PUBLIC: PROFILE & INIT ─────────────────────────────────────────────────

function Install-OpsPrerequisite {
    <#
    .SYNOPSIS
    Installs required PowerShell modules with publisher trust verification.
    .OUTPUTS
    PSCustomObject with Module, Status, Author, and CompanyName properties.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$ModuleName = $script:OpsRequiredModules
    )
    foreach ($module in $ModuleName) {
        if (Get-Module -ListAvailable -Name $module) {
            $trust = Test-OpsModulePublisher -ModuleName $module
            if (-not $trust.Trusted) {
                [PSCustomObject]@{
                    Module      = $module
                    Status      = $trust.Status
                    Message     = $trust.Message
                    Author      = $trust.Author
                    CompanyName = $trust.CompanyName
                }
                continue
            }
            [PSCustomObject]@{ Module = $module; Status = 'AlreadyInstalled'; Author = $trust.Author; CompanyName = $trust.CompanyName }
            continue
        }
        if ($PSCmdlet.ShouldProcess($module, 'Install PowerShell module for current user')) {
            try {
                Install-Module -Name $module -Scope CurrentUser -Force -ErrorAction Stop
                $trust = Test-OpsModulePublisher -ModuleName $module
                if (-not $trust.Trusted) {
                    [PSCustomObject]@{
                        Module      = $module
                        Status      = $trust.Status
                        Message     = $trust.Message
                        Author      = $trust.Author
                        CompanyName = $trust.CompanyName
                    }
                    continue
                }
                [PSCustomObject]@{ Module = $module; Status = 'Installed'; Author = $trust.Author; CompanyName = $trust.CompanyName }
            } catch {
                [PSCustomObject]@{ Module = $module; Status = 'Failed'; Message = $_.Exception.Message }
            }
        }
    }
}

function Import-OpsPrerequisite {
    <#
    .SYNOPSIS
    Imports required PowerShell modules and verifies publisher trust.
    .OUTPUTS
    PSCustomObject with Module, Status, Message, Author, and CompanyName properties.
    #>
    [CmdletBinding()]
    param(
        [string[]]$ModuleName = $script:OpsRequiredModules,
        [switch]$Quiet
    )
    $results = foreach ($module in $ModuleName) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            [PSCustomObject]@{ Module = $module; Status = 'Missing'; Message = 'Run Install-OpsPrerequisites' }
            continue
        }
        $trust = Test-OpsModulePublisher -ModuleName $module
        if (-not $trust.Trusted) {
            [PSCustomObject]@{
                Module      = $module
                Status      = $trust.Status
                Message     = $trust.Message
                Author      = $trust.Author
                CompanyName = $trust.CompanyName
            }
            continue
        }
        try {
            Import-Module -Name $module -ErrorAction SilentlyContinue 2>$null
            [PSCustomObject]@{ Module = $module; Status = 'Imported'; Message = ''; Author = $trust.Author; CompanyName = $trust.CompanyName }
        } catch {
            [PSCustomObject]@{ Module = $module; Status = 'Failed'; Message = $_.Exception.Message }
        }
    }
    if (-not $Quiet) { $results }
}

function Set-OpsReadLine {
    <#
    .SYNOPSIS
    Configures PSReadLine prediction source and ListView style.
    .OUTPUTS
    None.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) { return }
    if ($PSCmdlet.ShouldProcess('PSReadLine options', 'Configure prediction settings')) {
        try {
            Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        } catch { Write-Warning "PSReadLine configuration failed: $($_.Exception.Message)" }
    }
}

function Get-OpsPromptText {
    <#
    .SYNOPSIS
    Generates the custom PowerShell prompt with path, time, and git branch segments.
    .OUTPUTS
    String containing the formatted prompt with ANSI escape codes.
    #>
    [CmdletBinding()]
    param([bool]$LastSuccess = $true)
    $esc = [char]27
    $reset = "${esc}[0m"
    $path = (Get-Location).Path -replace "^$([Regex]::Escape([Environment]::GetFolderPath('UserProfile')))", '~'
    $pathSegment = "${esc}[48;5;158m${esc}[38;5;16m 󰉋 $path ${reset}"
    $timeSegment = "${esc}[48;5;244m${esc}[38;5;255m 󱑎 $([System.DateTime]::Now.ToString('HH:mm:ss')) ${reset}"
    $gitSegment = Get-OpsPromptGitSegment -Reset $reset
    $statusColor = if ($LastSuccess) { "${esc}[38;5;158m" } else { "${esc}[38;5;217m" }
    return "`n${pathSegment}${timeSegment}${gitSegment}`n${statusColor}󱞩 ${reset} "
}

function Get-OpsPromptGitSegment {
    <#
    .SYNOPSIS
    Returns the git branch segment for the custom prompt using filesystem caching.
    .OUTPUTS
    String containing the ANSI-formatted git branch name, or empty string if not in a repo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Used in cached scriptblock via closure')]
    [CmdletBinding()]
    param([string]$Reset)
    $cwd = $ExecutionContext.SessionState.Path.CurrentLocation.Path

    if (-not $script:OpsGitPromptBlock) {
        $script:OpsGitPromptBlock = {
            param([string]$currentDir, [string]$ansiReset)
            $gitDir = Join-Path $currentDir '.git'
            if (-not (Test-Path $gitDir)) {
                $parent = Split-Path $currentDir -Parent
                for ($i = 0; $i -lt 3 -and $parent; $i++) {
                    if (Test-Path (Join-Path $parent '.git')) {
                        $gitDir = Join-Path $parent '.git'
                        break
                    }
                    $parent = Split-Path $parent -Parent
                }
            }
            if (-not (Test-Path $gitDir)) { return '' }
            try {
                $headPath = Join-Path $gitDir 'HEAD'
                if (Test-Path $headPath) {
                    $headContent = Get-Content $headPath -Raw -ErrorAction SilentlyContinue
                    if ($headContent -match 'ref:\s+refs/heads/(.*)') {
                        $branch = $matches[1].Trim()
                        $esc = [char]27
                        return "${esc}[48;5;28m${esc}[38;5;255m 🌿 $branch [FS-Cached] ${ansiReset}"
                    }
                }
            } catch { Write-Verbose "Git prompt cache failed: $($_.Exception.Message)" }
            return ''
        }
    }

    return Invoke-OpsCachedData -Key "git_prompt_$cwd" -ExpirySeconds 3 -ScriptBlock {
        &$script:OpsGitPromptBlock $cwd $Reset
    }
}

function Set-OpsPrompt {
    <#
    .SYNOPSIS
    Sets the global prompt function to use Ops custom prompt segments.
    .OUTPUTS
    None.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if ($PSCmdlet.ShouldProcess('global:prompt', 'Set custom prompt function')) {
        if (-not (Get-Module oh-my-posh, posh-git -ErrorAction SilentlyContinue)) {
            Set-Item -Path Function:\global:Prompt -Value { Get-OpsPromptText -LastSuccess:$? }
        }
    }
}

function Set-OpsAliases {
    <#
    .SYNOPSIS
    Registers all Ops alias shortcuts in the global scope.
    .OUTPUTS
    None. Creates global aliases for all Ops utility functions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Intentionally sets all aliases in one call')]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if (-not $PSCmdlet.ShouldProcess('Global aliases', 'Set all Ops aliases')) { return }
    $mappings = @(
        @("corehealth", "Get-OpsHealth"),
        @("sysspec", "Get-OpsSpec"),
        @("sysuptime", "Get-OpsUptime"),
        @("ramstats", "Get-OpsRamInfo"),
        @("battstatus", "Get-OpsBattery"),
        @("gpuview", "Get-OpsDisplay"),
        @("powertriage", "Get-OpsPower"),
        @("vmcheck", "Get-OpsHypervisor"),
        @("liccheck", "Get-OpsLicense"),
        @("diskpressure", "Get-OpsDiskPressureAudit"),
        @("tempcheck", "Get-OpsTempCheck"),
        @("clipcheck", "Get-OpsClipCheck"),
        @("smartstatus", "Get-OpsDriveHealth"),
        @("resourcemap", "Get-OpsResourceMap"),
        @("portmap", "Get-OpsPortMap"),
        @("adminaudit", "Get-OpsAdmin"),
        @("shieldstatus", "Get-OpsShield"),
        @("fwcheck", "Get-OpsFirewallAudit"),
        @("bootmap", "Get-OpsBootMap"),
        @("taskrisk", "Get-OpsScheduledTaskRiskAudit"),
        @("ghostports", "Get-OpsGhostPortAudit"),
        @("susprocs", "Get-OpsSuspiciousProcessAudit"),
        @("eventstorm", "Get-OpsEventStormAudit"),
        @("certaudit", "Get-OpsCert"),
        @("dumpmap", "Get-OpsDump"),
        @("filecheck", "Get-OpsBadFile"),
        @("shortcutcheck", "Get-OpsLink"),
        @("lockcheck", "Get-OpsLock"),
        @("sparsecheck", "Get-OpsSparseFile"),
        @("compresscheck", "Get-OpsCompressedDir"),
        @("patchhistory", "Get-OpsPatchHistory"),
        @("driveraudit", "Get-OpsDriverAudit"),
        @("recentfiles", "Get-OpsRecent"),
        @("secretmask", "Protect-OpsSensitiveText"),
        @("netping", "Get-OpsNetCheck"),
        @("wificheck", "Get-OpsWifi"),
        @("peerscheck", "Get-OpsEstablished"),
        @("dnsbench", "Get-OpsDnsBench"),
        @("netspeed", "Get-OpsLinkSpeed"),
        @("smbshares", "Get-OpsShare"),
        @("hostscheck", "Get-OpsHostsCheck"),
        @("dnsmap", "Get-OpsDnsCache"),
        @("nettriage", "Get-OpsNetworkTriage"),
        @("envmap", "Get-OpsEnvMap"),
        @("pathaudit", "Get-OpsPathAudit"),
        @("applist", "Get-OpsApp"),
        @("apploc", "Get-OpsAppLocation"),
        @("askai", "Invoke-OpsAI"),
        @("websearch", "Invoke-OpsSearch"),
        @("aistatus", "Get-OpsAIStatus"),
        @("aiintent", "Get-OpsAIIntent"),
        @("aiprofile", "Get-OpsAIDataProfile"),
        @("sourcequality", "Get-OpsSourceQualityScore"),
        @("safetycheck", "Test-OpsPromptInjection"),
        @("airemember", "Add-OpsMemory"),
        @("airecall", "Search-OpsMemory"),
        @("memorymap", "Get-OpsMemoryMap"),
        @("memoryread", "Read-OpsMemory"),
        @("memoryfile", "Get-OpsMemoryFile"),
        @("fullreport", "New-OpsReport"),
        @("reportpath", "Get-OpsReportPath"),
        @("opsonboard", "Invoke-OpsOnboard"),
        @("onboardstep1", "Invoke-OpsOnboardStep1"),
        @("onboardstep2", "Invoke-OpsOnboardStep2"),
        @("onboardstep3", "Invoke-OpsOnboardStep3"),
        @("onboardstep4", "Invoke-OpsOnboardStep4"),
        @("onboardstep5", "Invoke-OpsOnboardStep5"),
        @("onboardstep6", "Invoke-OpsOnboardStep6"),
        @("coreindex", "Show-OpsDashboard"),
        @("watchindex", "Watch-OpsDashboard"),
        @("coremanual", "Show-OpsManual"),
        @("corereload", "Update-OpsProfile"),
        @("coreinit", "Initialize-OpsProfile"),
        @("cached", "Invoke-OpsCachedData"),
        @("proj", "Get-OpsProject"),
        @("projview", "Get-OpsProject"),
        @("projset", "Invoke-OpsProject"),
        @("openhere", "Invoke-ExplorerHere"),
        @("corecache", "Invoke-OpsCachedData"),
        @("sysdiag", "Get-OpsSystem"),
        @("auditdiag", "Get-OpsAudit"),
        @("netview", "Get-OpsNetwork"),
        @("envdiag", "Get-OpsEnv"),
        @("dailycheck", "Invoke-OpsDailyOps"),
        @("sysreview", "Invoke-OpsSystemReview"),
        @("secaudit", "Invoke-OpsSecurityAudit"),
        @("netreview", "Invoke-OpsNetworkDiagnostics"),
        @("threathunt", "Invoke-OpsThreatHunt"),
        @("changeaudit", "Invoke-OpsChangeAudit"),
        @("compliancecheck", "Invoke-OpsComplianceCheck"),
        @("hub", "Invoke-OpsCompanion"),
        @("ask", "Invoke-OpsShortAsk"),
        @("fix", "Invoke-OpsShortFix"),
        @("stat", "Invoke-OpsShortStat"),
        @("mem", "Invoke-OpsShortMem"),
        @("news", "Get-OpsDailyBrief"),
        @("brief", "Get-OpsDailyBrief")
    )
    foreach ($m in $mappings) {
        Set-Alias -Scope Global -Name $m[0] -Value $m[1] -Force
    }
}

function Initialize-OpsProfile {
    <#
    .SYNOPSIS
    Initializes the Ops module environment, imports prerequisites, and configures the shell.
    .OUTPUTS
    None. Sets up the Ops profile including aliases, prompt, and readline settings.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional user-facing config')]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$ProjectRoot = $script:OpsDefaultProjectRoot,
        [switch]$ShowDashboard,
        [switch]$SkipModules
    )
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $global:OpsProjectRoot = $ProjectRoot

    $isFirstRun = -not (Test-Path $script:OpsFirstRunSentinel)
    if ($isFirstRun -and (Test-OpsInteractiveSession)) {
        $esc = [char]27
        $gray = "${esc}[38;5;246m"
        $mint = "${esc}[48;5;158m${esc}[38;5;16m"
        $reset = "${esc}[0m"

        Write-Host ""
        Write-Host "  ${mint} POWERSHELL OPS : CORE ${reset} System provisioned. Version $($script:OpsVersion)."
        Write-Host "  ${gray}──────────────────────────────────────────────────────────${reset}"
        Write-Host "  Active environment: $ProjectRoot"
        Write-Host "  Architecture: 81 utilities | 7 workflows | Local AI"
        Write-Host ""

        if (-not (Test-OpsNerdFont)) {
            Write-Host "  ${gray}Note: Graphical symbols inactive. Install a Nerd Font for full UI.${reset}"
        }

        Write-Host "  Type 'coreindex' for index. 'dailycheck' for status."
        Write-Host ""
        try {
            $null = New-Item -Path $script:OpsFirstRunSentinel -ItemType File -Force -ErrorAction Stop
        } catch { Write-Verbose "Could not write first-run sentinel: $($_.Exception.Message)" }
    }

    if (-not $SkipModules) {
        Import-OpsPrerequisite -Quiet | Out-Null
    }

    Set-OpsReadLine
    Set-OpsAliases
    Set-OpsPrompt

    if ($ShowDashboard -and (Test-OpsInteractiveSession)) {
        Show-OpsDashboard
    }
}

function Update-OpsModule {
    <#
    .SYNOPSIS
    Pulls the latest code from git and reloads the module.
    .OUTPUTS
    None. Removes and re-imports the PowershellOps module from the repository.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('PowershellOps', 'Pull latest and reload')) {
        $moduleDir = $PSScriptRoot
        $repoRoot = $moduleDir
        for ($i = 0; $i -lt 5 -and $repoRoot; $i++) {
            if (Test-Path (Join-Path $repoRoot '.git')) { break }
            $parent = Split-Path $repoRoot -Parent
            if ($parent -eq $repoRoot) { $repoRoot = $null; break }
            $repoRoot = $parent
        }
        if (-not $repoRoot -or -not (Test-Path (Join-Path $repoRoot '.git'))) {
            Write-Warning "No git repository found for module path: $moduleDir"
            return
        }
        Push-Location $repoRoot
        try {
            Write-Information "  [Update] Pulling latest from git..." -InformationAction Continue
            git pull
            Write-Information "  [Update] Removing module from session..." -InformationAction Continue
            Remove-Module PowershellOps -Force -ErrorAction SilentlyContinue
            Write-Information "  [Update] Reloading..." -InformationAction Continue
            Import-Module (Join-Path $moduleDir 'PowershellOps.psd1') -Force -Global
            Write-Information "  [Update] PowershellOps reloaded." -InformationAction Continue
        } finally { Pop-Location }
    }
}

function Update-OpsProfile {
    <#
    .SYNOPSIS
    Re-dot-sources the current PowerShell profile to pick up changes.
    .OUTPUTS
    None. Reloads the current user's PowerShell profile script.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if (-not $PSCmdlet.ShouldProcess('$PROFILE', 'Dot-source profile')) { return }

    $profilePath = $null
    if ($PROFILE -is [System.Management.Automation.PSObject] -and $PROFILE.PSObject.Properties.Match('CurrentUserCurrentHost').Count -gt 0) {
        $profilePath = $PROFILE.CurrentUserCurrentHost
    } else {
        $profilePath = [string]$PROFILE
    }

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-Warning 'No profile path was available to reload.'
        return
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-Warning "Profile not found at: $profilePath"
        return
    }

    . $profilePath
}

function Show-OpsManual {
    <#
    .SYNOPSIS
    Opens the MANUAL.md reference file in the default editor.
    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    param()
    $manualPath = Join-Path $script:OpsWorkspaceRoot 'MANUAL.md'
    if (Test-Path $manualPath) {
        Write-Host "  Opening MANUAL.md..." -ForegroundColor Cyan
        Invoke-Item $manualPath
    } else {
        Write-Warning "Manual not found at: $manualPath"
    }
}

function Invoke-ExplorerHere {
    <#
    .SYNOPSIS
    Opens File Explorer at the current directory.
    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    param()
    Start-Process explorer.exe -ArgumentList (Get-Location).Path
}

function Get-OpsProject {
    <#
    .SYNOPSIS
    Returns the current Ops project root path.
    .OUTPUTS
    PSCustomObject with a CurrentRoot property containing the project root path.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional user-facing config')]
    [CmdletBinding()]
    param()
    [PSCustomObject]@{ CurrentRoot = ($global:OpsProjectRoot ?? $script:OpsDefaultProjectRoot) }
}

function Invoke-OpsProject {
    <#
    .SYNOPSIS
    Sets the global Ops project root path.
    .OUTPUTS
    PSCustomObject with a CurrentRoot property containing the newly set project root path.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional user-facing config')]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Path = $script:OpsDefaultProjectRoot)
    if ($PSCmdlet.ShouldProcess("Project root '$Path'", 'Set project root')) {
        $global:OpsProjectRoot = $Path
    }
    Get-OpsProject
}

function Get-OpsEnv {
    <#
    .SYNOPSIS
    Routes to a specific environment diagnostic function by type.
    .OUTPUTS
    PSCustomObject(s) from the corresponding diagnostic function.
    #>
    [CmdletBinding()]
    param([ValidateSet('Env','Path','App','Patch','Driver','Admin','Hypervisor','Power','License')][string]$Type = 'Env')
    switch ($Type) {
        'Env'        { Get-OpsEnvMap }
        'Path'       { Get-OpsPathAudit }
        'App'        { Get-OpsApp }
        'Patch'      { Get-OpsPatchHistory }
        'Driver'     { Get-OpsDriverAudit }
        'Admin'      { Get-OpsAdmin }
        'Hypervisor' { Get-OpsHypervisor }
        'Power'      { Get-OpsPower }
        'License'    { Get-OpsLicense }
    }
}


