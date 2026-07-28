# ── PUBLIC: ONBOARDING ─────────────────────────────────────────────────────

function Get-OpsOnboardContext {
    <#
    .SYNOPSIS
    Resolves the full onboarding context including project root, model catalog, and model file path.
    .OUTPUTS
    [PSCustomObject] containing resolved onboarding context.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $script:OpsDefaultProjectRoot,
        [string]$MemoryRoot,
        [string]$AIEndpoint = $script:OpsDefaultAIEndpoint,
        [string]$Model,
        [string]$ModelFilePath = (Join-Path $script:OpsConfigRoot 'OpsIntelligence.generated.Modelfile')
    )

    $projectRootResolved = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $script:OpsDefaultProjectRoot } else { $ProjectRoot }
    $memoryRootResolved = if ([string]::IsNullOrWhiteSpace($MemoryRoot)) { Join-Path $projectRootResolved 'Memory' } else { $MemoryRoot }
    $catalog = Get-OpsOllamaModelCatalog -Endpoint $AIEndpoint
    $selectedModel = Resolve-OpsAIModel -PreferredModel $Model -AvailableModels $catalog.Models

    [PSCustomObject]@{
        ProjectRoot        = $projectRootResolved
        MemoryRoot         = $memoryRootResolved
        AIEndpoint         = $AIEndpoint
        Model              = $selectedModel
        AvailableModels    = @($catalog.Models | Select-Object -ExpandProperty Name -Unique)
        ModelCatalogSource  = $catalog.Source
        ModelCatalogStatus  = if ($catalog.Models.Count -gt 0) { 'Available' } else { 'Unavailable' }
        ModelCatalogMessage = $catalog.Message
        ModelFilePath      = $ModelFilePath
    }
}

function Save-OpsOnboardConfiguration {
    <#
    .SYNOPSIS
    Persists onboarding configuration to the ops-settings.json file.
    .OUTPUTS
    [PSCustomObject] with the written configuration values.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [string]$MemoryRoot,
        [string]$AIEndpoint,
        [string]$AIModel,
        [string]$ModelFilePath,
        [bool]$SetupCompleted = $false
    )

    $current = Read-OpsConfiguration
    $config = [ordered]@{
        ProjectRoot    = $current.ProjectRoot
        MemoryRoot     = $current.MemoryRoot
        AIEndpoint     = $current.AIEndpoint
        AIModel        = $current.AIModel
        ModelFile      = $current.ModelFile
        SetupCompleted = [bool]$SetupCompleted
    }

    if ($PSBoundParameters.ContainsKey('ProjectRoot')) { $config.ProjectRoot = $ProjectRoot }
    if ($PSBoundParameters.ContainsKey('MemoryRoot')) { $config.MemoryRoot = $MemoryRoot }
    if ($PSBoundParameters.ContainsKey('AIEndpoint')) { $config.AIEndpoint = $AIEndpoint }
    if ($PSBoundParameters.ContainsKey('AIModel')) { $config.AIModel = $AIModel }
    if ($PSBoundParameters.ContainsKey('ModelFilePath')) { $config.ModelFile = $ModelFilePath }

    $written = Write-OpsConfiguration -Configuration $config

    if ($written.ProjectRoot) {
        $script:OpsDefaultProjectRoot = $written.ProjectRoot
        $global:OpsProjectRoot = $written.ProjectRoot
    }
    if ($written.MemoryRoot) {
        $script:OpsMemoryRoot = $written.MemoryRoot
        $script:OpsMemoryFile = Join-Path $script:OpsMemoryRoot 'ops-memory.jsonl'
    }
    if ($written.AIEndpoint) { $script:OpsDefaultAIEndpoint = $written.AIEndpoint }
    if ($written.AIModel) { $script:OpsDefaultAIModel = $written.AIModel }
    if ($written.ModelFile) { $script:OpsAIModelFile = $written.ModelFile }

    [PSCustomObject]$written
}

function New-OpsOnboardModelfile {
    <#
    .SYNOPSIS
    Generates a Modelfile from the template with the selected model.
    .OUTPUTS
    [PSCustomObject] indicating the created Modelfile details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SelectedModel,
        [string]$ModelFilePath = (Join-Path $script:OpsConfigRoot 'OpsIntelligence.generated.Modelfile'),
        [string]$TemplatePath = (Join-Path $script:OpsWorkspaceRoot 'modelfiles\OpsIntelligence.Modelfile')
    )

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "Modelfile template not found at: $TemplatePath"
    }

    $template = Get-Content -Path $TemplatePath -Raw -ErrorAction Stop
    $generated = $template -replace '(?m)^FROM\s+.+$', "FROM $SelectedModel"
    $generated = $generated -replace 'powershell-ops:latest', "powershell-ops:$SelectedModel"

    $parent = Split-Path -Path $ModelFilePath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -Path $parent -ItemType Directory -Force
    }

    $generated | Set-Content -Path $ModelFilePath -Encoding UTF8

    [PSCustomObject]@{
        TemplatePath = $TemplatePath
        ModelFilePath = $ModelFilePath
        Model        = $SelectedModel
        Created      = $true
    }
}

function New-OpsOnboardStepPlan {
    <#
    .SYNOPSIS
    Returns a structured plan of onboarding steps with status and commands.
    .OUTPUTS
    Array of [PSCustomObject] representing each onboarding step.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    @(
        [PSCustomObject]@{
            Step        = 1
            Alias       = 'onboardstep1'
            Title       = 'Set the project root'
            Status      = 'Auto'
            Command     = "Invoke-OpsOnboardStep1 -ProjectRoot '$($Context.ProjectRoot)'"
            AliasCommand = "onboardstep1 -ProjectRoot '$($Context.ProjectRoot)'"
            Description = 'Runs immediately with the resolved default project root unless you override it.'
        },
        [PSCustomObject]@{
            Step        = 2
            Alias       = 'onboardstep2'
            Title       = 'Set the local memory root'
            Status      = 'Auto'
            Command     = "Invoke-OpsOnboardStep2 -ProjectRoot '$($Context.ProjectRoot)' -MemoryRoot '$($Context.MemoryRoot)'"
            AliasCommand = "onboardstep2 -ProjectRoot '$($Context.ProjectRoot)' -MemoryRoot '$($Context.MemoryRoot)'"
            Description = 'Runs immediately with the default memory root derived from the project root unless you override it.'
        },
        [PSCustomObject]@{
            Step        = 3
            Alias       = 'onboardstep3'
            Title       = 'Wire the Ollama backend'
            Status      = if ($Context.ModelCatalogStatus -eq 'Available') { 'Ready' } else { 'Needs manual setup' }
            Command     = "Invoke-OpsOnboardStep3 -AIEndpoint '$($Context.AIEndpoint)'"
            AliasCommand = "onboardstep3 -AIEndpoint '$($Context.AIEndpoint)'"
            Description = 'Checks the Ollama endpoint and discovers local models via `ollama list` or `/api/tags`.'
        },
        [PSCustomObject]@{
            Step        = 4
            Alias       = 'onboardstep4'
            Title       = 'Pick the AI model'
            Status      = if ($Context.Model) { 'Selected' } else { 'Unresolved' }
            Command     = "Invoke-OpsOnboardStep4 -AIEndpoint '$($Context.AIEndpoint)' -Model '$($Context.Model)'"
            AliasCommand = "onboardstep4 -AIEndpoint '$($Context.AIEndpoint)' -Model '$($Context.Model)'"
            Description = 'Selects an installed local model. If the preferred model is missing, the first available model is used.'
        },
        [PSCustomObject]@{
            Step        = 5
            Alias       = 'onboardstep5'
            Title       = 'Generate a local Modelfile'
            Status      = 'Auto'
            Command     = "Invoke-OpsOnboardStep5 -Model '$($Context.Model)' -ModelFilePath '$($Context.ModelFilePath)'"
            AliasCommand = "onboardstep5 -Model '$($Context.Model)' -ModelFilePath '$($Context.ModelFilePath)'"
            Description = 'Creates the Modelfile automatically from the bundled template. This is the step that makes the file.'
        },
        [PSCustomObject]@{
            Step        = 6
            Alias       = 'onboardstep6'
            Title       = 'Create the Ollama model'
            Status      = 'Auto'
            Command     = "Invoke-OpsOnboardStep6 -ModelName 'powershell-ops' -ModelFilePath '$($Context.ModelFilePath)'"
            AliasCommand = "onboardstep6 -ModelName 'powershell-ops' -ModelFilePath '$($Context.ModelFilePath)'"
            Description = 'Runs `ollama create` against the generated Modelfile after you review it.'
        }
    )
}

function Invoke-OpsOnboardStep1 {
    <#
    .SYNOPSIS
    Sets the project root in the onboarding configuration.
    .OUTPUTS
    [PSCustomObject] with the applied project root.
    #>
    [CmdletBinding()]
    param([string]$ProjectRoot = $script:OpsDefaultProjectRoot)

    $resolvedProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $script:OpsDefaultProjectRoot } else { $ProjectRoot }
    Save-OpsOnboardConfiguration -ProjectRoot $resolvedProjectRoot | Out-Null

    [PSCustomObject]@{
        Step        = 1
        Alias       = 'onboardstep1'
        ProjectRoot = $resolvedProjectRoot
        Applied     = $true
    }
}

function Invoke-OpsOnboardStep2 {
    <#
    .SYNOPSIS
    Sets the memory root directory and saves it to configuration.
    .OUTPUTS
    [PSCustomObject] with the applied memory root.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $script:OpsDefaultProjectRoot,
        [string]$MemoryRoot
    )

    $resolvedProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $script:OpsDefaultProjectRoot } else { $ProjectRoot }
    $resolvedMemoryRoot = if ([string]::IsNullOrWhiteSpace($MemoryRoot)) { Join-Path $resolvedProjectRoot 'Memory' } else { $MemoryRoot }
    $null = New-Item -Path $resolvedMemoryRoot -ItemType Directory -Force
    Save-OpsOnboardConfiguration -ProjectRoot $resolvedProjectRoot -MemoryRoot $resolvedMemoryRoot | Out-Null

    [PSCustomObject]@{
        Step       = 2
        Alias      = 'onboardstep2'
        ProjectRoot = $resolvedProjectRoot
        MemoryRoot = $resolvedMemoryRoot
        Applied    = $true
    }
}

function Invoke-OpsOnboardStep3 {
    <#
    .SYNOPSIS
    Tests Ollama endpoint connectivity and discovers available models.
    .OUTPUTS
    [PSCustomObject] with model catalog details.
    #>
    [CmdletBinding()]
    param([string]$AIEndpoint = $script:OpsDefaultAIEndpoint)

    $catalog = Get-OpsOllamaModelCatalog -Endpoint $AIEndpoint
    Save-OpsOnboardConfiguration -AIEndpoint $AIEndpoint | Out-Null

    [PSCustomObject]@{
        Step               = 3
        Alias              = 'onboardstep3'
        AIEndpoint         = $AIEndpoint
        ModelCatalogSource = $catalog.Source
        ModelCatalogStatus = if ($catalog.Models.Count -gt 0) { 'Available' } else { 'Unavailable' }
        ModelCatalogMessage = $catalog.Message
        ModelCount         = @($catalog.Models).Count
        Applied            = $true
    }
}

function Invoke-OpsOnboardStep4 {
    <#
    .SYNOPSIS
    Selects the AI model from the available catalog and saves it.
    .OUTPUTS
    [PSCustomObject] with the selected model and catalog info.
    #>
    [CmdletBinding()]
    param(
        [string]$AIEndpoint = $script:OpsDefaultAIEndpoint,
        [string]$Model
    )

    $context = Get-OpsOnboardContext -AIEndpoint $AIEndpoint -Model $Model
    Save-OpsOnboardConfiguration -AIEndpoint $context.AIEndpoint -AIModel $context.Model | Out-Null

    [PSCustomObject]@{
        Step               = 4
        Alias              = 'onboardstep4'
        AIEndpoint         = $context.AIEndpoint
        Model              = $context.Model
        AvailableModels    = $context.AvailableModels
        ModelCatalogSource = $context.ModelCatalogSource
        ModelCatalogStatus = $context.ModelCatalogStatus
        ModelCatalogMessage = $context.ModelCatalogMessage
        Applied            = $true
    }
}

function Invoke-OpsOnboardStep5 {
    <#
    .SYNOPSIS
    Generates the Ollama Modelfile from the bundled template.
    .OUTPUTS
    [PSCustomObject] with the generated Modelfile path and status.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $script:OpsDefaultProjectRoot,
        [string]$MemoryRoot,
        [string]$AIEndpoint = $script:OpsDefaultAIEndpoint,
        [string]$Model,
        [string]$ModelFilePath = (Join-Path $script:OpsConfigRoot 'OpsIntelligence.generated.Modelfile'),
        [string]$TemplatePath = (Join-Path $script:OpsWorkspaceRoot 'modelfiles\OpsIntelligence.Modelfile')
    )

    $context = Get-OpsOnboardContext -ProjectRoot $ProjectRoot -MemoryRoot $MemoryRoot -AIEndpoint $AIEndpoint -Model $Model -ModelFilePath $ModelFilePath
    $null = New-OpsOnboardModelfile -SelectedModel $context.Model -ModelFilePath $context.ModelFilePath -TemplatePath $TemplatePath
    Save-OpsOnboardConfiguration -ProjectRoot $context.ProjectRoot -MemoryRoot $context.MemoryRoot -AIEndpoint $context.AIEndpoint -AIModel $context.Model -ModelFilePath $context.ModelFilePath | Out-Null

    [PSCustomObject]@{
        Step         = 5
        Alias        = 'onboardstep5'
        Model        = $context.Model
        ModelFilePath = $context.ModelFilePath
        TemplatePath = $TemplatePath
        Created      = Test-Path -LiteralPath $context.ModelFilePath
        Applied      = $true
    }
}

function Invoke-OpsOnboardStep6 {
    <#
    .SYNOPSIS
    Creates the Ollama model by running ollama create against the generated Modelfile.
    .OUTPUTS
    [PSCustomObject] with the model creation result.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$ModelName = 'powershell-ops',
        [string]$ModelFilePath = (Join-Path $script:OpsConfigRoot 'OpsIntelligence.generated.Modelfile'),
        [string]$AIEndpoint = $script:OpsDefaultAIEndpoint
    )

    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        throw 'ollama command was not found. Install Ollama or ensure it is on PATH before running onboardstep6.'
    }

    if (-not (Test-Path -LiteralPath $ModelFilePath)) {
        throw "Modelfile not found at: $ModelFilePath"
    }

    if ($PSCmdlet.ShouldProcess("Ollama model '$ModelName'", 'Create from Modelfile')) {
        & ollama create $ModelName -f $ModelFilePath
    }
    Save-OpsOnboardConfiguration -AIEndpoint $AIEndpoint -ModelFilePath $ModelFilePath -SetupCompleted $true | Out-Null

    [PSCustomObject]@{
        Step         = 6
        Alias        = 'onboardstep6'
        ModelName    = $ModelName
        ModelFilePath = $ModelFilePath
        AIEndpoint   = $AIEndpoint
        Applied      = $true
    }
}

function Invoke-OpsOnboard {
    <#
    .SYNOPSIS
    Runs the full onboarding workflow with context resolution, step planning, and optional apply.
    .OUTPUTS
    [PSCustomObject] with the full onboarding context and step plan.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional user-facing config')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ProjectRoot = $script:OpsDefaultProjectRoot,
        [string]$MemoryRoot = (Join-Path $ProjectRoot 'Memory'),
        [string]$AIEndpoint = $script:OpsDefaultAIEndpoint,
        [string]$Model,
        [string]$ModelFilePath = (Join-Path $script:OpsConfigRoot 'OpsIntelligence.generated.Modelfile'),
        [switch]$Apply
    )

    $context = Get-OpsOnboardContext -ProjectRoot $ProjectRoot -MemoryRoot $MemoryRoot -AIEndpoint $AIEndpoint -Model $Model -ModelFilePath $ModelFilePath
    $steps = New-OpsOnboardStepPlan -Context $context

    if ($Apply -and $PSCmdlet.ShouldProcess('Onboarding configuration', 'Save onboarding state')) {
        $null = New-Item -Path $context.MemoryRoot -ItemType Directory -Force
        Save-OpsOnboardConfiguration -ProjectRoot $context.ProjectRoot -MemoryRoot $context.MemoryRoot -AIEndpoint $context.AIEndpoint -AIModel $context.Model -ModelFilePath $context.ModelFilePath | Out-Null
        $null = New-OpsOnboardModelfile -SelectedModel $context.Model -ModelFilePath $context.ModelFilePath
    }

    [PSCustomObject]@{
        ProjectRoot        = $context.ProjectRoot
        MemoryRoot         = $context.MemoryRoot
        AIEndpoint         = $context.AIEndpoint
        Model              = $context.Model
        AvailableModels    = $context.AvailableModels
        ModelCatalogSource = $context.ModelCatalogSource
        ModelCatalogStatus = $context.ModelCatalogStatus
        ModelCatalogMessage = $context.ModelCatalogMessage
        ModelFilePath      = $context.ModelFilePath
        Steps              = $steps
        Applied            = [bool]$Apply
    }
}
