$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflowPath = Join-Path $repositoryRoot '.github/workflows/app.yml'
$migratorPath = Join-Path $repositoryRoot 'tools/Shopping.DatabaseMigrator/Program.cs'
$workflow = Get-Content -LiteralPath $workflowPath -Raw
$migrator = Get-Content -LiteralPath $migratorPath -Raw

if ($workflow -notmatch '--query clientId' -or
    $workflow -notmatch 'SHOPPING_API_CLIENT_ID="\$api_client_id"') {
    throw 'The app workflow must provision the SQL user from the API managed identity client ID.'
}

if ($workflow -match 'shopping-prod' -or
    $workflow -match 'fromJSON\(needs\.deployment-target\.outputs\.runner\)') {
    throw 'Production deployment must not depend on an externally managed self-hosted runner.'
}

$productionRegistryAccessPattern = "(?s)Open temporary production registry access.*az acr network-rule add.*--ip-address.*az acr update.*--public-network-enabled true"
$productionRegistryCleanupPattern = "(?s)Close temporary production registry access.*always\(\).*az acr update.*--public-network-enabled false.*az acr network-rule remove"

if ($workflow -notmatch $productionRegistryAccessPattern -or
    $workflow -notmatch $productionRegistryCleanupPattern) {
    throw 'Production image deployment must temporarily allowlist the hosted runner and always restore private ACR access.'
}

$productionSqlAccessPattern = "(?s)Open temporary SQL firewall rule.*az sql server update.*--enable-public-network true"
$productionSqlCleanupPattern = "(?s)Remove temporary SQL firewall rule.*always\(\).*az sql server update.*--enable-public-network false"

if ($workflow -notmatch $productionSqlAccessPattern -or
    $workflow -notmatch $productionSqlCleanupPattern) {
    throw 'Production migration must temporarily allowlist the hosted runner and always restore private SQL access.'
}

if ($migrator -notmatch 'GetRequiredEnvironmentVariable\("SHOPPING_API_CLIENT_ID"\)' -or
    $migrator -match 'SHOPPING_API_PRINCIPAL_ID') {
    throw 'The database migrator must use SHOPPING_API_CLIENT_ID as the service-principal SID.'
}

if ($migrator -notmatch "(?s)IF EXISTS \(.*name = N'.*sid <> 0x\{principalSid\}.*DROP USER \[\{escapedPrincipalName\}\].*IF NOT EXISTS \(.*name = N'.*sid = 0x\{principalSid\}.*CREATE USER") {
    throw 'The database migrator must replace a same-name SQL user whose managed-identity SID changed.'
}

Write-Host 'Application deployment workflow is valid.'
