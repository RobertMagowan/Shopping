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

if ($sqlModule -notmatch 'param\s+sqlZoneRedundant\s+bool' -or
    $sqlModule -notmatch 'zoneRedundant:\s*sqlZoneRedundant' -or
    $sqlModule -match "zoneRedundant:\s*environmentName == 'prod'") {
    throw 'sql.bicep must use the explicit SQL zone-redundancy capability parameter.'
}

$redisModulePath = Join-Path $infraRoot 'modules/redis.bicep'
$redisModule = Get-Content -LiteralPath $redisModulePath -Raw

if ($orchestrator -notmatch 'param\s+managedRedisLocation\s+string' -or
    $orchestrator -notmatch 'param\s+sqlZoneRedundant\s+bool' -or
    $orchestrator -notmatch 'location:\s*managedRedisLocation' -or
    $orchestrator -notmatch 'sqlZoneRedundant:\s*sqlZoneRedundant') {
    throw 'environment.bicep must pass explicit Redis location and SQL zone-redundancy capabilities.'
}

if ($redisModule -notmatch 'param\s+location\s+string') {
    throw 'redis.bicep must accept its deployment location from the environment orchestrator.'
}

$devParameters = Get-Content -LiteralPath (Join-Path $infraRoot 'parameters/dev.bicepparam') -Raw
$testParameters = Get-Content -LiteralPath (Join-Path $infraRoot 'parameters/test.bicepparam') -Raw
$prodParameters = Get-Content -LiteralPath (Join-Path $infraRoot 'parameters/prod.bicepparam') -Raw

if ($prodParameters -notmatch "readEnvironmentVariable\('MANAGED_REDIS_LOCATION',\s*'uksouth'\)" -or
    $prodParameters -notmatch "readEnvironmentVariable\('SQL_ZONE_REDUNDANT',\s*'true'\)") {
    throw 'Production parameters must expose subscription-specific Redis location and SQL zone-redundancy controls.'
}

foreach ($nonProductionParameters in @($devParameters, $testParameters)) {
    if ($nonProductionParameters -notmatch "readEnvironmentVariable\('SQL_ZONE_REDUNDANT',\s*'false'\)") {
        throw 'Every environment must consume the SQL_ZONE_REDUNDANT workflow contract.'
    }
}

$redisModuleCall = [regex]::Match(
    $orchestrator,
    "(?ms)^module\s+redis\s+'redis\.bicep'.*?(?=^module\s|^output\s|\z)"
)
$privateEndpointsModuleCall = [regex]::Match(
    $orchestrator,
    "(?ms)^module\s+privateEndpoints\s+'private-endpoints\.bicep'.*?(?=^module\s|^output\s|\z)"
)

if (-not $redisModuleCall.Success -or
    $redisModuleCall.Value -notmatch 'location:\s*managedRedisLocation' -or
    -not $privateEndpointsModuleCall.Success -or
    $privateEndpointsModuleCall.Value -notmatch 'location:\s*location' -or
    $privateEndpointsModuleCall.Value -match 'location:\s*managedRedisLocation') {
    throw 'Managed Redis may use a separate region, but private endpoints must remain in the application region.'
}

if ($orchestrator -notmatch "var\s+sqlPrivateDnsZoneName\s*=\s*'privatelink\$\{environment\(\)\.suffixes\.sqlServerHostname\}'" -or
    $orchestrator -match "'privatelink\.\$\{environment\(\)\.suffixes\.sqlServerHostname\}'") {
    throw 'The SQL private DNS zone must not add a second dot before the Azure SQL hostname suffix.'
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

$imageDeliveryModulePath = Join-Path $infraRoot 'modules/image-delivery.bicep'
$imageDeliveryModule = Get-Content -LiteralPath $imageDeliveryModulePath -Raw
$cdnResourceMatches = [regex]::Matches(
    $imageDeliveryModule,
    "'Microsoft\.Cdn/[^']+@(?<apiVersion>[^']+)'"
)

if ($cdnResourceMatches.Count -ne 5 -or
    @($cdnResourceMatches | Where-Object { $_.Groups['apiVersion'].Value -ne '2025-06-01' }).Count -gt 0) {
    throw 'Front Door resources must use the supported stable Microsoft.Cdn API version 2025-06-01.'
}

$frontDoorOriginMatch = [regex]::Match(
    $imageDeliveryModule,
    "(?ms)^resource\s+frontDoorOrigin\s+'Microsoft\.Cdn/profiles/originGroups/origins@2025-06-01'.*?(?=^resource\s|^output\s|\z)"
)

if (-not $frontDoorOriginMatch.Success -or
    $frontDoorOriginMatch.Value -notmatch 'sharedPrivateLinkResource:\s*\{' -or
    $frontDoorOriginMatch.Value -notmatch 'groupId:\s*\x27blob\x27' -or
    $frontDoorOriginMatch.Value -match 'privateLinkResourceId|privateLinkSubResourceType') {
    throw 'The Front Door origin must use the supported sharedPrivateLinkResource shape for its private Blob origin.'
}

Write-Host 'Bicep module structure is valid.'
