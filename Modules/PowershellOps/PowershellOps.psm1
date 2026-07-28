# ==============================================================================
# PowershellOps 11.3 - Integrated Operational Core Engine (Production Refactored)
# ==============================================================================
# Private helpers + Public functions are dot-sourced from Private/*.ps1 and Public/*.ps1

$script:OpsVersion = '11.3'
$script:OpsAppName = 'PowershellOps'
$script:OpsVibe    = 'Modern'
$script:OpsRequiredModules = @('Terminal-Icons', 'PSReadLine', 'PSTree')
$script:OpsTrustedModulePublishers = @{
    'Terminal-Icons' = @{ Author = 'Brandon Olin'; CompanyName = 'devblackops' }
    'PSReadLine'     = @{ Author = 'Microsoft Corporation'; CompanyName = 'PowerShellTeam' }
    'PSTree'         = @{ Author = 'Santiago Squarzon'; CompanyName = 'santisq' }
}

# Prefer explicit app/data roots so the profile can live under E:\Projects\apps
# and generated state can live under E:\Projects\data.
$script:OpsAppsRoot = if ($env:Ops_APPS_ROOT) { $env:Ops_APPS_ROOT } elseif ($env:Ops_APP_ROOT) { $env:Ops_APP_ROOT } else { $null }
$script:OpsDataRoot = if ($env:Ops_DATA_ROOT) { $env:Ops_DATA_ROOT } elseif ($env:Ops_STORAGE_ROOT) { $env:Ops_STORAGE_ROOT } else { $null }

$script:OpsWorkspaceRoot = if ($script:OpsAppsRoot) {
    $script:OpsAppsRoot
} elseif ($PSScriptRoot) {
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} elseif ($PROFILE -and $PROFILE.CurrentUserCurrentHost) {
    Split-Path -Parent $PROFILE.CurrentUserCurrentHost
} else {
    Join-Path $HOME 'Projects'
}

$script:OpsConfigRoot = if ($script:OpsDataRoot) { Join-Path $script:OpsDataRoot 'Config' } else { Join-Path $script:OpsWorkspaceRoot 'Config' }
$script:OpsConfigFile = Join-Path $script:OpsConfigRoot 'ops-settings.json'
$script:OpsDefaultAIEndpoint = 'http://127.0.0.1:11434'
$script:OpsDefaultAIModel = 'OpsPowershell'
$script:OpsAIModelFile = $null
$script:OpsDefaultProjectRoot = if ($env:Ops_PROJECT_ROOT) { $env:Ops_PROJECT_ROOT } elseif ($script:OpsWorkspaceRoot) { $script:OpsWorkspaceRoot } elseif ($PROFILE -and $PROFILE.CurrentUserCurrentHost) { Split-Path -Parent $PROFILE.CurrentUserCurrentHost } else { Join-Path $HOME 'Projects' }
$script:OpsSuppressHeaders = $false
$script:OpsSensitiveNamePattern = '(?i)(secret|token|password|passwd|pwd|credential|connection.?string|sas|bearer|api.?key|private.?key)'
$script:OpsLastFirewallFilterError = $null
$script:OpsReportRoot = if ($script:OpsDataRoot) { Join-Path $script:OpsDataRoot 'Reports' } else { Join-Path $script:OpsWorkspaceRoot 'Reports' }
$script:OpsMemoryRoot = if ($script:OpsDataRoot) { Join-Path $script:OpsDataRoot 'Memory' } else { Join-Path $script:OpsWorkspaceRoot 'Memory' }
$script:OpsMemoryFile = Join-Path $script:OpsMemoryRoot 'ops-memory.jsonl'
$script:OpsFirstRunSentinel = if ($script:OpsDataRoot) { Join-Path $script:OpsDataRoot '.Ops_first_run' } else { Join-Path $script:OpsWorkspaceRoot '.Ops_first_run' }

# Initialize thread-safe data store cache allocation
if (-not $script:OpsCacheStore) {
    $script:OpsCacheStore = [hashtable]::Synchronized(@{})
}

# Initialize search rate-limiting tracker
$script:OpsLastSearchTime = $null

# -- DOT-SOURCE PRIVATE HELPERS ------------------------------------------------
$privatePath = Join-Path $PSScriptRoot 'Private'
Get-ChildItem "$privatePath\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

# Load persisted onboarding choices if present.
Import-OpsConfiguration | Out-Null

# Environment-driven roots should win over persisted defaults so the shell can
# be relocated cleanly to E:\Projects\apps and E:\Projects\data.
if ($env:Ops_PROJECT_ROOT) {
    $script:OpsDefaultProjectRoot = $env:Ops_PROJECT_ROOT
    $global:OpsProjectRoot = $env:Ops_PROJECT_ROOT
}
if ($env:Ops_DATA_ROOT) {
    $script:OpsMemoryRoot = Join-Path $env:Ops_DATA_ROOT 'Memory'
    $script:OpsMemoryFile = Join-Path $script:OpsMemoryRoot 'ops-memory.jsonl'
    $script:OpsReportRoot = Join-Path $env:Ops_DATA_ROOT 'Reports'
    $script:OpsFirstRunSentinel = Join-Path $env:Ops_DATA_ROOT '.Ops_first_run'
}

# -- DOT-SOURCE PUBLIC FUNCTIONS ----------------------------------------------
$publicPath = Join-Path $PSScriptRoot 'Public'
Get-ChildItem "$publicPath\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

# Register the user-facing aliases as soon as the module is imported so the
# onboarding shortcuts work without requiring a separate profile initializer.
try {
    Set-OpsAliases | Out-Null
} catch {
    Write-Verbose "Alias registration failed during module import: $($_.Exception.Message)"
}

# -- MODULE EXPORT -------------------------------------------------------------
Export-ModuleMember -Function @(
    'Add-OpsMemory',
    'Build-OpsAIContextPacket',
    'Build-OpsAIMemoryContext',
    'ConvertTo-OpsMarkdownTable',
    'ConvertTo-OpsReportMarkdown',
    'Format-OpsMarkdownCell',
    'Format-OpsMemoryId',
    'Format-OpsMemorySnippet',
    'Format-OpsReportCell',
    'Get-OpsAdmin',
    'Get-OpsAIDataProfile',
    'Get-OpsAIIntent',
    'Get-OpsAIStatus',
    'Get-OpsApp',
    'Get-OpsAppLocation',
    'Get-OpsAudit',
    'Get-OpsBadFile',
    'Get-OpsBattery',
    'Get-OpsDailyBrief',
    'Get-OpsBootMap',
    'Get-OpsCert',
    'Get-OpsClipCheck',
    'Get-OpsCompressedDir',
    'Get-OpsDiskPressureAudit',
    'Get-OpsDisplay',
    'Get-OpsDnsBench',
    'Get-OpsDnsCache',
    'Get-OpsDriveHealth',
    'Get-OpsDriverAudit',
    'Get-OpsDump',
    'Get-OpsEnv',
    'Get-OpsEnvMap',
    'Get-OpsEstablished',
    'Get-OpsEventStormAudit',
    'Get-OpsFirewallAudit',
    'Get-OpsGhostPortAudit',
    'Get-OpsHealth',
    'Get-OpsHostsCheck',
    'Get-OpsHypervisor',
    'Get-OpsLicense',
    'Get-OpsLink',
    'Get-OpsLinkSpeed',
    'Get-OpsLock',
    'Get-OpsMemoryFile',
    'Get-OpsMemoryMap',
    'Get-OpsMemorySearchTerm',
    'Get-OpsNetCheck',
    'Get-OpsNetwork',
    'Get-OpsNetworkTriage',
    'Get-OpsOnboardContext',
    'Get-OpsOllamaModelCatalog',
    'Get-OpsPatchHistory',
    'Get-OpsPathAudit',
    'Get-OpsPortMap',
    'Get-OpsPower',
    'Get-OpsProject',
    'Get-OpsPromptGitSegment',
    'Get-OpsPromptText',
    'Get-OpsRamInfo',
    'Get-OpsRecent',
    'Get-OpsReportPath',
    'Get-OpsResourceMap',
    'Get-OpsScheduledTaskRiskAudit',
    'Get-OpsShare',
    'Get-OpsShield',
    'Get-OpsSourceQualityScore',
    'Get-OpsSparseFile',
    'Get-OpsSpec',
    'Get-OpsSuspiciousProcessAudit',
    'Get-OpsSystem',
    'Get-OpsTempCheck',
    'Get-OpsUptime',
    'Get-OpsVectorSimilarity',
    'Get-OpsWifi',
    'Import-OpsPrerequisite',
    'Initialize-OpsProfile',
    'Install-OpsPrerequisite',
    'Invoke-ExplorerHere',
    'Invoke-OpsAI',
    'Invoke-OpsAIEmbedding',
    'Invoke-OpsShortAsk',
    'Invoke-OpsShortFix',
    'Invoke-OpsShortStat',
    'Invoke-OpsShortMem',
    'Invoke-OpsCompanion',
    'Invoke-OpsCachedData',
    'Invoke-OpsChangeAudit',
    'Invoke-OpsComplianceCheck',
    'Invoke-OpsDailyOps',
    'Invoke-OpsNetworkDiagnostics',
    'Invoke-OpsOnboard',
    'Invoke-OpsOnboardStep1',
    'Invoke-OpsOnboardStep2',
    'Invoke-OpsOnboardStep3',
    'Invoke-OpsOnboardStep4',
    'Invoke-OpsOnboardStep5',
    'Invoke-OpsOnboardStep6',
    'Invoke-OpsProject',
    'Invoke-OpsSearch',
    'Invoke-OpsSecurityAudit',
    'Invoke-OpsSystemReview',
    'Invoke-OpsThreatHunt',
    'New-OpsOnboardModelfile',
    'New-OpsOnboardStepPlan',
    'New-OpsReport',
    'Protect-OpsSensitiveText',
    'Read-OpsMemory',
    'Resolve-OpsAIModel',
    'Resolve-OpsDuckDuckGoHref',
    'Save-OpsOnboardConfiguration',
    'Search-OpsMemory',
    'Set-OpsAliases',
    'Set-OpsPrompt',
    'Set-OpsReadLine',
    'Show-OpsDashboard',
    'Show-OpsManual',
    'Test-OpsInteractiveSession',
    'Test-OpsModulePublisher',
    'Test-OpsPromptInjection',
    'Update-OpsModule',
    'Update-OpsMemoryEmbeddings',
    'Update-OpsProfile',
    'Watch-OpsDashboard',
    'Write-OpsHeader',
    'Write-OpsReportTable'
) -Alias *


