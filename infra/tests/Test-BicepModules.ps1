$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$infraRoot = Split-Path -Parent $PSScriptRoot
$orchestratorPath = Join-Path $infraRoot 'modules/environment.bicep'
$orchestrator = Get-Content -LiteralPath $orchestratorPath -Raw
$requiredModules = @(
    'network'
    'container-platform'
    'identities'
    'container-registry'
    'key-vault'
    'storage'
    'sql'
    'redis'
    'image-delivery'
    'access-control'
    'private-endpoints'
    'container-apps'
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

$resourceDeclarations = [regex]::Matches($orchestrator, '(?m)^resource\s+').Count
if ($resourceDeclarations -gt 0) {
    throw "environment.bicep must orchestrate modules only; found $resourceDeclarations resource declarations."
}

$sqlModulePath = Join-Path $infraRoot 'modules/sql.bicep'
$sqlModule = Get-Content -LiteralPath $sqlModulePath -Raw
$devSqlCredentialsPattern = "(?s)\.\.\.\(environmentName == 'dev' \? \{.*administratorLogin:\s*sqlAdministratorLogin.*administratorLoginPassword:\s*sqlAdministratorPassword.*\} : \{\}\)"

if ($sqlModule -notmatch $devSqlCredentialsPattern) {
    throw 'sql.bicep must supply SQL administrator credentials only in dev.'
}

if ($sqlModule -notmatch "azureADOnlyAuthentication:\s*environmentName != 'dev'") {
    throw 'sql.bicep must enable Entra-only authentication outside dev.'
}

$publicSqlFirewallRuleMatch = [regex]::Match(
    $sqlModule,
    "(?ms)^resource\s+allowAzureServices\s+'Microsoft.Sql/servers/firewallRules@[^']+'\s*=\s*if\s*\(!enablePrivateEndpoints\).*?(?=^resource\s|^output\s|\z)"
)

if (-not $publicSqlFirewallRuleMatch.Success) {
    throw 'sql.bicep must allow Azure-hosted callers when SQL private endpoints are disabled.'
}

$publicSqlFirewallRule = $publicSqlFirewallRuleMatch.Value

if ($publicSqlFirewallRule -notmatch 'parent:\s*sqlServer' -or
    $publicSqlFirewallRule -notmatch "name:\s*'AllowAllWindowsAzureIps'" -or
    $publicSqlFirewallRule -notmatch "startIpAddress:\s*'0\.0\.0\.0'" -or
    $publicSqlFirewallRule -notmatch "endIpAddress:\s*'0\.0\.0\.0'") {
    throw 'The public SQL firewall resource must target sqlServer and use the Azure-services 0.0.0.0 rule.'
}

Write-Host 'Bicep module structure is valid.'
