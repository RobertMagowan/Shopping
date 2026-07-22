$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflowPath = Join-Path $repositoryRoot '.github/workflows/app.yml'
$migratorPath = Join-Path $repositoryRoot 'tools/Shopping.DatabaseMigrator/Program.cs'
$workflow = Get-Content -LiteralPath $workflowPath -Raw
$migrator = Get-Content -LiteralPath $migratorPath -Raw

function Get-WorkflowStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $stepMatch = [regex]::Match(
        $workflow,
        "(?ms)^\s{6}- name:\s*$escapedName\s*`r?`n.*?(?=^\s{6}- name:|\z)"
    )

    if (-not $stepMatch.Success) {
        throw "Application deployment step '$Name' is missing."
    }

    return $stepMatch.Value
}

$migrationStep = Get-WorkflowStep -Name 'Apply database migrations and runtime permissions'
$openRegistryStep = Get-WorkflowStep -Name 'Open temporary production registry access'
$closeRegistryStep = Get-WorkflowStep -Name 'Close temporary production registry access'
$openSqlStep = Get-WorkflowStep -Name 'Open temporary SQL firewall rule'
$closeSqlStep = Get-WorkflowStep -Name 'Remove temporary SQL firewall rule'

if ($migrationStep -notmatch '--query clientId' -or
    $migrationStep -notmatch 'SHOPPING_API_CLIENT_ID="\$api_client_id"') {
    throw 'The app workflow must provision the SQL user from the API managed identity client ID.'
}

if ($workflow -match 'shopping-prod' -or
    $workflow -match 'fromJSON\(needs\.deployment-target\.outputs\.runner\)') {
    throw 'Production deployment must not depend on an externally managed self-hosted runner.'
}

if ($openRegistryStep -notmatch '(?s)az acr network-rule add.*--ip-address.*az acr update.*--public-network-enabled true' -or
    $closeRegistryStep -notmatch 'always\(\)' -or
    $closeRegistryStep -notmatch '(?s)az acr update.*--public-network-enabled false.*az acr network-rule remove') {
    throw 'Production image deployment must temporarily allowlist the hosted runner and always restore private ACR access.'
}

if ($openSqlStep -notmatch '(?s)az sql server update.*--enable-public-network true.*az sql server firewall-rule create' -or
    $closeSqlStep -notmatch 'always\(\)' -or
    $closeSqlStep -notmatch '(?s)az sql server firewall-rule delete.*az sql server update.*--enable-public-network false') {
    throw 'Production migration must temporarily allowlist the hosted runner and always restore private SQL access.'
}

if ($migrator -notmatch 'GetRequiredEnvironmentVariable\("SHOPPING_API_CLIENT_ID"\)' -or
    $migrator -match 'SHOPPING_API_PRINCIPAL_ID') {
    throw 'The database migrator must use SHOPPING_API_CLIENT_ID as the service-principal SID.'
}

$principalSqlMatch = [regex]::Match($migrator, '(?s)var principalSql = \$"""(?<sql>.*?)""";')

if (-not $principalSqlMatch.Success) {
    throw 'The database migrator principal reconciliation SQL is missing.'
}

$principalSql = $principalSqlMatch.Groups['sql'].Value

if ($principalSql -notmatch "(?s)IF EXISTS \(.*name = N'.*sid <> 0x\{principalSid\}.*DROP USER \[\{escapedPrincipalName\}\].*IF NOT EXISTS \(.*name = N'.*sid = 0x\{principalSid\}.*CREATE USER") {
    throw 'The database migrator must replace a same-name SQL user whose managed-identity SID changed.'
}

Write-Host 'Application deployment workflow is valid.'
