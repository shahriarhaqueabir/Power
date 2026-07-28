# ==============================================================================
# Ops : CORE : v11.3
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Path Resolution
$OpsProfileRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ($PROFILE.CurrentUserCurrentHost ?? (Get-Location).Path) }
$OpsModuleManifest = Join-Path $OpsProfileRoot 'Modules\PowershellOps\PowershellOps.psd1'

# Module Verification
if (-not (Test-Path $OpsModuleManifest)) {
    # Silence warning during standard shell startup if module is missing
    return
}

# Core Initialization
try {
    Import-Module $OpsModuleManifest -Force -ErrorAction Stop
    $OpsProjectRoot = if ($env:Ops_PROJECT_ROOT) { $env:Ops_PROJECT_ROOT } else { $OpsProfileRoot }
    Initialize-OpsProfile -ProjectRoot $OpsProjectRoot -ShowDashboard
}
catch {
    Write-Warning "[ Ops ] Core initialization failure: $($_.Exception.Message)"
}

# Integrate external tools if present
if (Get-Command scoop-search -ErrorAction SilentlyContinue) {
    . ([ScriptBlock]::Create((& scoop-search --hook | Out-String))) | Out-Null
}


