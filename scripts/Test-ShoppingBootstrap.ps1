[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$StatePath = ".\scripts\bootstrap-state.local.json"
)

. "$PSScriptRoot\bootstrap-shared.ps1"

$results = [Collections.Generic.List[object]]::new()

function Add-VerificationResult {
    param(
        [string]$Area,
        [ValidateSet("Pass", "Fail", "Manual")]
        [string]$Status,
        [string]$Detail
    )

    $results.Add([pscustomobject]@{
        Area = $Area
        Status = $Status
        Detail = $Detail
    })
}

function Invoke-GraphGet {
    param(
        [string]$TenantId,
        [string]$Uri
    )

    $token = & az account get-access-token --tenant $TenantId --resource-type ms-graph --query accessToken -o tsv --only-show-errors

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to acquire a Microsoft Graph token for tenant '$TenantId'. Sign in to that tenant first."
    }

    try {
        Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $token" }
    }
    finally {
        $token = $null
    }
}

function Test-SetEquality {
    param(
        [object[]]$Actual,
        [object[]]$Expected
    )

    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    return @(Compare-Object -ReferenceObject $expectedValues -DifferenceObject $actualValues -CaseSensitive).Count -eq 0
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Bootstrap configuration '$ConfigPath' does not exist."
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    throw "Bootstrap state '$StatePath' does not exist. Run Initialize-ShoppingBootstrap.ps1 first."
}

Assert-Command -Name "az"
Assert-Command -Name "gh"
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$state = Read-BootstrapState -Path $StatePath
$canonicalRepository = Get-CanonicalGitHubRepository -Repository $config.Repository
$oidcSubjectPrefix = Get-GitHubOidcSubjectPrefix -Repository $canonicalRepository
$configuredInstanceName = [string](Get-ObjectPropertyValue -InputObject $config -Name "InstanceName")
$deploymentInstance = Get-DeploymentInstanceName `
    -ConfiguredInstanceName $configuredInstanceName `
    -CanonicalRepository $canonicalRepository
$publicWebBaseUrls = Get-ObjectPropertyValue -InputObject $config.ExternalId -Name "PublicWebBaseUrls"
$expectedWebRedirectUris = Get-AuthoritativeWebRedirectUris `
    -ConfiguredRedirectUris @($config.ExternalId.WebRedirectUris) `
    -SubscriptionId $config.Azure.SubscriptionId `
    -WorkloadName $config.WorkloadName `
    -InstanceName $deploymentInstance `
    -Environments @($config.Environments) `
    -PublicWebBaseUrls $publicWebBaseUrls
$stateInstanceName = [string](Get-ObjectPropertyValue -InputObject $state.bootstrap -Name "instanceName")

if ($state.bootstrap.repository -ceq $canonicalRepository -and
    $stateInstanceName -ceq $deploymentInstance) {
    Add-VerificationResult -Area "State" -Status "Pass" -Detail "Canonical repository is $canonicalRepository and deployment instance is $deploymentInstance."
}
else {
    Add-VerificationResult -Area "State" -Status "Fail" -Detail "State repository/instance '$($state.bootstrap.repository)/$stateInstanceName' differs from '$canonicalRepository/$deploymentInstance'."
}

$stateText = Get-Content -Raw -LiteralPath $StatePath

if ($stateText -match '"(password|clientSecret|secretValue)"\s*:') {
    Add-VerificationResult -Area "State" -Status "Fail" -Detail "The non-secret state file contains a forbidden secret-like property."
}
else {
    Add-VerificationResult -Area "State" -Status "Pass" -Detail "No secret values are represented in bootstrap state."
}

try {
    $deploymentApp = Invoke-GraphGet -TenantId $state.azure.tenantId -Uri "https://graph.microsoft.com/v1.0/applications/$($state.azure.deploymentApplicationObjectId)"
    $credentials = Invoke-GraphGet -TenantId $state.azure.tenantId -Uri "https://graph.microsoft.com/v1.0/applications/$($state.azure.deploymentApplicationObjectId)/federatedIdentityCredentials"
    $expectedSubjects = @($config.Environments | ForEach-Object { "$oidcSubjectPrefix`:environment:$_" })
    $actualSubjects = @($credentials.value | Where-Object { $_.name -like "github-*" } | ForEach-Object subject)
    $stateSubjectPrefix = Get-ObjectPropertyValue -InputObject $state.bootstrap -Name "oidcSubjectPrefix"
    $expectedDeploymentAppName = "$($config.WorkloadName)-$deploymentInstance-github-deploy"

    if ($deploymentApp.appId -eq $state.azure.deploymentApplicationClientId -and
        $deploymentApp.displayName -eq $expectedDeploymentAppName -and
        $stateSubjectPrefix -ceq $oidcSubjectPrefix -and
        (Test-SetEquality -Actual $actualSubjects -Expected $expectedSubjects)) {
        Add-VerificationResult -Area "Azure OIDC" -Status "Pass" -Detail "Deployment application and case-sensitive environment subjects match state."
    }
    else {
        Add-VerificationResult -Area "Azure OIDC" -Status "Fail" -Detail "Actual subjects '$($actualSubjects -join ', ')' differ from '$($expectedSubjects -join ', ')'."
    }
}
catch {
    Add-VerificationResult -Area "Azure OIDC" -Status "Fail" -Detail $_.Exception.Message
}

try {
    $assignments = Invoke-AzJson -Arguments @(
        "role", "assignment", "list",
        "--subscription", $state.azure.subscriptionId,
        "--assignee-object-id", $state.azure.deploymentServicePrincipalObjectId
    )
    $actualRoles = @($assignments | ForEach-Object roleDefinitionName)
    $expectedRoles = @($config.Azure.DeploymentRoles)

    if (Test-SetEquality -Actual $actualRoles -Expected $expectedRoles) {
        Add-VerificationResult -Area "Azure RBAC" -Status "Pass" -Detail "Deployment identity has the configured subscription roles."
    }
    else {
        Add-VerificationResult -Area "Azure RBAC" -Status "Fail" -Detail "Actual roles '$($actualRoles -join ', ')' differ from '$($expectedRoles -join ', ')'."
    }
}
catch {
    Add-VerificationResult -Area "Azure RBAC" -Status "Fail" -Detail $_.Exception.Message
}

try {
    $webApp = Invoke-GraphGet -TenantId $state.externalId.tenantId -Uri "https://graph.microsoft.com/v1.0/applications/$($state.externalId.webApplicationObjectId)"
    $apiApp = Invoke-GraphGet -TenantId $state.externalId.tenantId -Uri "https://graph.microsoft.com/v1.0/applications/$($state.externalId.apiApplicationObjectId)"
    $expectedRoles = @("Admin", "CatalogManager", "Customer")
    $webRoles = @($webApp.appRoles | Where-Object isEnabled | ForEach-Object value)
    $apiRoles = @($apiApp.appRoles | Where-Object isEnabled | ForEach-Object value)
    $webNameMatches = $webApp.displayName -eq "$($config.WorkloadName)-$deploymentInstance-web"
    $apiNameMatches = $apiApp.displayName -eq "$($config.WorkloadName)-$deploymentInstance-api"
    $redirectsMatch = Test-SetEquality -Actual $webApp.web.redirectUris -Expected $expectedWebRedirectUris
    $scopeMatches = @($apiApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "access_as_user" -and $_.isEnabled }).Count -eq 1

    if ($webNameMatches -and $apiNameMatches -and
        $redirectsMatch -and $scopeMatches -and
        (Test-SetEquality -Actual $webRoles -Expected $expectedRoles) -and
        (Test-SetEquality -Actual $apiRoles -Expected $expectedRoles)) {
        Add-VerificationResult -Area "External ID apps" -Status "Pass" -Detail "Redirect URIs, roles, and access_as_user scope match authoritative configuration."
    }
    else {
        $differences = @()

        if (-not $webNameMatches -or -not $apiNameMatches) { $differences += "application names" }
        if (-not $redirectsMatch) { $differences += "redirect URIs" }
        if (-not $scopeMatches) { $differences += "access_as_user scope" }
        if (-not (Test-SetEquality -Actual $webRoles -Expected $expectedRoles)) { $differences += "Web roles" }
        if (-not (Test-SetEquality -Actual $apiRoles -Expected $expectedRoles)) { $differences += "API roles" }
        Add-VerificationResult -Area "External ID apps" -Status "Fail" -Detail "Managed values differ: $($differences -join ', ')."
    }

    $filter = [Uri]::EscapeDataString("clientId eq '$($state.externalId.webServicePrincipalObjectId)'")
    $grants = Invoke-GraphGet -TenantId $state.externalId.tenantId -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter"
    $consent = @($grants.value | Where-Object {
        $_.resourceId -eq $state.externalId.apiServicePrincipalObjectId -and
        $_.consentType -eq "AllPrincipals" -and
        @($_.scope -split ' ') -contains "access_as_user"
    })

    if ($consent.Count -eq 1) {
        Add-VerificationResult -Area "External ID consent" -Status "Pass" -Detail "Tenant-wide access_as_user consent exists."
    }
    else {
        Add-VerificationResult -Area "External ID consent" -Status "Fail" -Detail "Tenant-wide access_as_user consent was not found."
    }
}
catch {
    Add-VerificationResult -Area "External ID apps" -Status "Fail" -Detail $_.Exception.Message
}

$bootstrapAdminUserObjectId = [string]$config.ExternalId.BootstrapAdminUserObjectId

if ([string]::IsNullOrWhiteSpace($bootstrapAdminUserObjectId)) {
    $bootstrapAdminUserObjectId = [string](Get-ObjectPropertyValue `
        -InputObject $state.externalId `
        -Name "bootstrapAdminUserObjectId")
}

if ([string]::IsNullOrWhiteSpace($bootstrapAdminUserObjectId)) {
    Add-VerificationResult -Area "Bootstrap Admin" -Status "Manual" -Detail "No initial Admin object ID is configured."
}
else {
    try {
        $webAssignments = Invoke-GraphGet -TenantId $state.externalId.tenantId -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($state.externalId.webServicePrincipalObjectId)/appRoleAssignedTo"
        $apiAssignments = Invoke-GraphGet -TenantId $state.externalId.tenantId -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($state.externalId.apiServicePrincipalObjectId)/appRoleAssignedTo"
        $webAdminRoleId = @($webApp.appRoles | Where-Object value -eq "Admin")[0].id
        $apiAdminRoleId = @($apiApp.appRoles | Where-Object value -eq "Admin")[0].id
        $webAssigned = @($webAssignments.value | Where-Object { $_.principalId -eq $bootstrapAdminUserObjectId -and $_.appRoleId -eq $webAdminRoleId }).Count -eq 1
        $apiAssigned = @($apiAssignments.value | Where-Object { $_.principalId -eq $bootstrapAdminUserObjectId -and $_.appRoleId -eq $apiAdminRoleId }).Count -eq 1

        if ($webAssigned -and $apiAssigned) {
            Add-VerificationResult -Area "Bootstrap Admin" -Status "Pass" -Detail "Initial administrator is assigned to both Web and API Admin roles."
        }
        else {
            Add-VerificationResult -Area "Bootstrap Admin" -Status "Fail" -Detail "Initial administrator is missing one or both Admin assignments."
        }
    }
    catch {
        Add-VerificationResult -Area "Bootstrap Admin" -Status "Fail" -Detail $_.Exception.Message
    }
}

$requiredVariables = @(
    "AZURE_CLIENT_ID",
    "AZURE_PRINCIPAL_OBJECT_ID",
    "AZURE_TENANT_ID",
    "AZURE_SUBSCRIPTION_ID",
    "WORKLOAD_NAME",
    "DEPLOYMENT_INSTANCE",
    "RESOURCE_SUFFIX",
    "SQL_ADMINISTRATOR_LOGIN",
    "ENTRA_EXTERNAL_ID_INSTANCE",
    "ENTRA_EXTERNAL_ID_DOMAIN",
    "ENTRA_EXTERNAL_ID_TENANT_ID",
    "ENTRA_EXTERNAL_ID_WEB_CLIENT_ID",
    "ENTRA_EXTERNAL_ID_API_CLIENT_ID",
    "ENTRA_EXTERNAL_ID_API_AUDIENCE",
    "SHOPPING_API_SCOPE"
)
$requiredSecrets = @("SQL_ADMINISTRATOR_PASSWORD", "ENTRA_EXTERNAL_ID_WEB_CLIENT_SECRET")

foreach ($environmentName in $config.Environments) {
    try {
        $environment = & gh api "repos/$canonicalRepository/environments/$environmentName" | ConvertFrom-Json
        $environmentVariables = @((& gh api "repos/$canonicalRepository/environments/$environmentName/variables?per_page=100" | ConvertFrom-Json).variables)
        $variables = $environmentVariables.name
        $secrets = (& gh api "repos/$canonicalRepository/environments/$environmentName/secrets" | ConvertFrom-Json).secrets.name
        $missingVariables = @($requiredVariables | Where-Object { $variables -notcontains $_ })
        $missingSecrets = @($requiredSecrets | Where-Object { $secrets -notcontains $_ })
        $expectedResourceSuffix = Get-EnvironmentResourceSuffix `
            -SubscriptionId $config.Azure.SubscriptionId `
            -WorkloadName $config.WorkloadName `
            -InstanceName $deploymentInstance `
            -EnvironmentName $environmentName
        $resourceSuffixVariable = @($environmentVariables | Where-Object name -eq "RESOURCE_SUFFIX")
        $resourceSuffixCorrect = $resourceSuffixVariable.Count -eq 1 -and
                                 $resourceSuffixVariable[0].value -ceq $expectedResourceSuffix
        $workloadVariable = @($environmentVariables | Where-Object name -eq "WORKLOAD_NAME")
        $workloadCorrect = $workloadVariable.Count -eq 1 -and
                           $workloadVariable[0].value -ceq $config.WorkloadName
        $instanceVariable = @($environmentVariables | Where-Object name -eq "DEPLOYMENT_INSTANCE")
        $instanceCorrect = $instanceVariable.Count -eq 1 -and
                           $instanceVariable[0].value -ceq $deploymentInstance
        $valuesPresent = $missingVariables.Count -eq 0 -and
                         $missingSecrets.Count -eq 0 -and
                         $resourceSuffixCorrect -and
                         $workloadCorrect -and
                         $instanceCorrect
        $protectionCorrect = if ($environmentName -eq "prod") {
            $deploymentBranchPolicy = Get-ObjectPropertyValue -InputObject $environment -Name "deployment_branch_policy"
            $customBranchPolicies = Get-ObjectPropertyValue -InputObject $deploymentBranchPolicy -Name "custom_branch_policies"
            $branchPolicies = @()

            if ($customBranchPolicies -eq $true) {
                $branchPolicies = @((& gh api "repos/$canonicalRepository/environments/prod/deployment-branch-policies" | ConvertFrom-Json).branch_policies)
            }

            $exactBranchPolicy = @($branchPolicies | Where-Object { $_.name -ceq $config.Branch -and $_.type -eq "branch" })

            @($environment.protection_rules | Where-Object type -eq "required_reviewers").Count -eq 1 -and
            $customBranchPolicies -eq $true -and
            $exactBranchPolicy.Count -eq 1 -and
            @($branchPolicies).Count -eq 1
        }
        else {
            @($environment.protection_rules).Count -eq 0
        }

        if ($valuesPresent -and $protectionCorrect) {
            Add-VerificationResult -Area "GitHub/$environmentName" -Status "Pass" -Detail "Variables, secrets, and deployment protection are configured."
        }
        else {
            $differences = @()

            if ($missingVariables.Count -gt 0) { $differences += "missing variables: $($missingVariables -join ', ')" }
            if ($missingSecrets.Count -gt 0) { $differences += "missing secrets: $($missingSecrets -join ', ')" }
            if (-not $resourceSuffixCorrect) { $differences += "RESOURCE_SUFFIX differs from '$expectedResourceSuffix'" }
            if (-not $workloadCorrect) { $differences += "WORKLOAD_NAME differs from '$($config.WorkloadName)'" }
            if (-not $instanceCorrect) { $differences += "DEPLOYMENT_INSTANCE differs from '$deploymentInstance'" }
            if (-not $protectionCorrect) { $differences += "deployment protection" }
            Add-VerificationResult -Area "GitHub/$environmentName" -Status "Fail" -Detail ($differences -join '; ')
        }
    }
    catch {
        Add-VerificationResult -Area "GitHub/$environmentName" -Status "Fail" -Detail $_.Exception.Message
    }
}

try {
    $rulesetsJson = & gh api "repos/$canonicalRepository/rulesets?includes_parents=false"
    $rulesets = @($rulesetsJson | ConvertFrom-Json)
    $ruleset = @($rulesets | Where-Object { $_.name -eq $config.GitHub.RulesetName })

    if ($ruleset.Count -eq 1 -and $ruleset[0].enforcement -eq "active") {
        $rulesetDetails = & gh api "repos/$canonicalRepository/rulesets/$($ruleset[0].id)" | ConvertFrom-Json
        $requiredStatusChecksRule = @($rulesetDetails.rules | Where-Object type -eq "required_status_checks")
        $actualStatusChecks = @($requiredStatusChecksRule.parameters.required_status_checks.context | Sort-Object)
        $expectedStatusChecks = @(Get-RequiredGitHubStatusChecks | Sort-Object)
        $statusChecksMatch = $requiredStatusChecksRule.Count -eq 1 -and
                             @(Compare-Object -ReferenceObject $expectedStatusChecks -DifferenceObject $actualStatusChecks -CaseSensitive).Count -eq 0

        if ($statusChecksMatch) {
            Add-VerificationResult -Area "GitHub ruleset" -Status "Pass" -Detail "Managed ruleset and required status checks match configuration."
        }
        else {
            Add-VerificationResult -Area "GitHub ruleset" -Status "Fail" -Detail "Managed ruleset required status checks differ from configuration."
        }
    }
    else {
        Add-VerificationResult -Area "GitHub ruleset" -Status "Fail" -Detail "Managed ruleset is missing, duplicated, or inactive."
    }
}
catch {
    Add-VerificationResult -Area "GitHub ruleset" -Status "Fail" -Detail $_.Exception.Message
}

Add-VerificationResult -Area "User flow" -Status "Manual" -Detail "Confirm the customer user flow includes Shopping.Web and the required identity providers in the Entra portal."
$results | Format-Table -AutoSize -Wrap | Out-Host

$failures = @($results | Where-Object Status -eq "Fail")

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Bootstrap verification found $($failures.Count) configuration area(s) that do not match the desired state." -ForegroundColor Red
    Write-Host "Review the Fail rows above. Apply Initialize-ShoppingBootstrap.ps1 without -WhatIf, then run this verifier again."
    exit 1
}

Write-Host "Automated bootstrap verification passed. Complete the Manual checks before declaring the environment ready."
