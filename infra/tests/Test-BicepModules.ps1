$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$infraRoot = Split-Path -Parent $PSScriptRoot
$orchestratorPath = Join-Path $infraRoot 'modules/environment.bicep'
$orchestrator = Get-Content -LiteralPath $orchestratorPath -Raw
$requiredModules = @(
    'network'
    'container-platform'
)

foreach ($moduleName in $requiredModules) {
    $modulePath = Join-Path $infraRoot "modules/$moduleName.bicep"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required Bicep module is missing: $moduleName.bicep"
    }

    if ($orchestrator -notmatch "module\s+\w+\s+'$([regex]::Escape($moduleName)).bicep'") {
        throw "environment.bicep does not invoke $moduleName.bicep"
    }
}

Write-Host 'Bicep module structure is valid.'
