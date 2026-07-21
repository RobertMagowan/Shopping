[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WorkloadName = "shopping",

    [Parameter(Mandatory = $true)]
    [string]$InstanceName,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ExternalIdInstance,

    [Parameter(Mandatory = $true)]
    [string]$ExternalIdDomain,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$WebRedirectUris,

    [string]$StatePath = ".\scripts\bootstrap-state.local.json",

    [int]$WebClientSecretYears = 1,

    [switch]$RotateWebClientSecret,

    [switch]$GrantAdminConsent,

    [string]$BootstrapAdminEmail,

    [string]$BootstrapAdminUserObjectId,

    [switch]$PassThru
)

. "$PSScriptRoot\bootstrap-shared.ps1"

function Get-ManagedApplication {
    param(
        [object]$StateSection,
        [string]$StatePropertyName,
        [string]$DisplayName,
        [string]$LegacyDisplayName
    )

    $objectId = Get-ObjectPropertyValue -InputObject $StateSection -Name $StatePropertyName
    $application = Get-ApplicationByObjectId -ObjectId $objectId

    if (-not [string]::IsNullOrWhiteSpace([string]$objectId) -and $null -eq $application) {
        throw "Application '$objectId' recorded in '$StatePath' no longer exists. Review the state before creating or adopting another application."
    }

    if ($null -eq $application) {
        $application = Get-ApplicationByDisplayName -DisplayName $DisplayName
    }

    if ($null -ne $application -and $application.displayName -ne $DisplayName) {
        if (-not [string]::IsNullOrWhiteSpace($LegacyDisplayName) -and
            $application.displayName -eq $LegacyDisplayName -and
            $PSCmdlet.ShouldProcess($application.displayName, "Rename state-pinned application to '$DisplayName'")) {
            Invoke-AzJson -Arguments @("ad", "app", "update", "--id", $application.id, "--display-name", $DisplayName) | Out-Null
            $application = Get-ApplicationByObjectId -ObjectId $application.id
        }
        elseif ($application.displayName -ne $LegacyDisplayName) {
            throw "State points to application '$($application.displayName)', expected '$DisplayName'."
        }
    }

    return $application
}

function New-ManagedApplication {
    param([string]$DisplayName)

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create External ID application")) {
        return $null
    }

    Invoke-AzJson -Arguments @("ad", "app", "create", "--display-name", $DisplayName, "--sign-in-audience", "AzureADMyOrg")
}

function Get-ApplicationRoles {
    param([object]$Application)

    @(
        @{
            id = "$(New-DeterministicGuid -Value "$($Application.appId):Admin")"
            allowedMemberTypes = @("User")
            displayName = "Admin"
            value = "Admin"
            description = "Administrators can manage users, catalog, products, and pricing."
            isEnabled = $true
        },
        @{
            id = "$(New-DeterministicGuid -Value "$($Application.appId):Customer")"
            allowedMemberTypes = @("User")
            displayName = "Customer"
            value = "Customer"
            description = "Customers can browse products and use the shopping cart."
            isEnabled = $true
        },
        @{
            id = "$(New-DeterministicGuid -Value "$($Application.appId):CatalogManager")"
            allowedMemberTypes = @("User")
            displayName = "CatalogManager"
            value = "CatalogManager"
            description = "Catalog managers can manage products, images, pricing, and availability."
            isEnabled = $true
        }
    )
}

function Set-ApiApplicationConfiguration {
    param(
        [object]$Application,
        [object[]]$Roles
    )

    $scopeId = New-DeterministicGuid -Value "$($Application.appId):access_as_user"
    $body = @{
        identifierUris = @("api://$($Application.appId)")
        api = @{
            oauth2PermissionScopes = @(
                @{
                    id = "$scopeId"
                    value = "access_as_user"
                    type = "User"
                    isEnabled = $true
                    adminConsentDisplayName = "Access Shopping API"
                    adminConsentDescription = "Allows the application to access Shopping.Api as the signed-in user."
                    userConsentDisplayName = "Access Shopping API"
                    userConsentDescription = "Allows the application to access Shopping.Api as you."
                }
            )
        }
        appRoles = $Roles
    }

    if ($PSCmdlet.ShouldProcess($Application.displayName, "Replace script-owned API scope, identifier URI, and app roles")) {
        Invoke-AzRestJson -Method "PATCH" -Uri "https://graph.microsoft.com/v1.0/applications/$($Application.id)" -Body $body | Out-Null
    }

    return [pscustomobject]@{
        ScopeId = "$scopeId"
        Audience = "api://$($Application.appId)"
        Scope = "api://$($Application.appId)/access_as_user"
    }
}

function Set-WebApplicationConfiguration {
    param(
        [object]$WebApplication,
        [object]$ApiApplication,
        [string]$ApiScopeId,
        [object[]]$Roles,
        [string[]]$RedirectUris
    )

    $body = @{
        web = @{
            redirectUris = @($RedirectUris | Sort-Object -Unique)
            implicitGrantSettings = @{
                enableAccessTokenIssuance = $false
                enableIdTokenIssuance = $true
            }
        }
        requiredResourceAccess = @(
            @{
                resourceAppId = $ApiApplication.appId
                resourceAccess = @(
                    @{
                        id = $ApiScopeId
                        type = "Scope"
                    }
                )
            }
        )
        appRoles = $Roles
    }

    if ($PSCmdlet.ShouldProcess($WebApplication.displayName, "Replace script-owned redirect URIs, API permission, and app roles")) {
        Invoke-AzRestJson -Method "PATCH" -Uri "https://graph.microsoft.com/v1.0/applications/$($WebApplication.id)" -Body $body | Out-Null
    }
}

function Get-OrCreateServicePrincipal {
    param([object]$Application)

    $servicePrincipal = Get-ServicePrincipalByAppId -AppId $Application.appId

    if ($null -ne $servicePrincipal) {
        return $servicePrincipal
    }

    if (-not $PSCmdlet.ShouldProcess($Application.displayName, "Create service principal")) {
        return $null
    }

    return Ensure-ServicePrincipal -AppId $Application.appId
}

function Set-AdminRoleAssignment {
    param(
        [string]$UserObjectId,
        [object]$Application,
        [object]$ServicePrincipal,
        [object[]]$Roles
    )

    $adminRole = $Roles | Where-Object { $_.value -eq "Admin" } | Select-Object -First 1
    $assignments = Invoke-AzRestJson -Method "GET" -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ServicePrincipal.id)/appRoleAssignedTo" -Body $null
    $existing = @($assignments.value | Where-Object {
        $_.principalId -eq $UserObjectId -and $_.appRoleId -eq $adminRole.id
    })

    if ($existing.Count -gt 0) {
        return
    }

    $body = @{
        principalId = $UserObjectId
        resourceId = $ServicePrincipal.id
        appRoleId = $adminRole.id
    }

    if ($PSCmdlet.ShouldProcess("$UserObjectId -> $($Application.displayName):Admin", "Create bootstrap Admin app-role assignment")) {
        Invoke-AzRestJson -Method "POST" -Uri "https://graph.microsoft.com/v1.0/users/$UserObjectId/appRoleAssignments" -Body $body | Out-Null
    }
}

function New-WebClientSecret {
    param([string]$WebApplicationId)

    $credential = Invoke-AzJson -Arguments @(
        "ad", "app", "credential", "reset",
        "--id", $WebApplicationId,
        "--append",
        "--display-name", "shopping-bootstrap",
        "--years", "$WebClientSecretYears"
    )

    return ConvertTo-SecureString -String $credential.password -AsPlainText -Force
}

Assert-Command -Name "az"
Assert-EntraContext -TenantId $TenantId

$normalizedRedirectUris = @($WebRedirectUris | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

if ($normalizedRedirectUris.Count -eq 0) {
    throw "Provide the complete authoritative Shopping.Web redirect URI list."
}

$state = Read-BootstrapState -Path $StatePath
$rootState = Get-OrAddStateSection -State $state -Name "bootstrap"
Assert-StateValue -StateSection $rootState -Name "workloadName" -ExpectedValue $WorkloadName
Assert-StateValue -StateSection $rootState -Name "instanceName" -ExpectedValue $InstanceName

$externalIdState = Get-OrAddStateSection -State $state -Name "externalId"
Assert-StateValue -StateSection $externalIdState -Name "tenantId" -ExpectedValue $TenantId
Assert-StateValue -StateSection $externalIdState -Name "domain" -ExpectedValue $ExternalIdDomain
Assert-StateValue -StateSection $externalIdState -Name "instance" -ExpectedValue $ExternalIdInstance

$apiDisplayName = "$WorkloadName-$InstanceName-api"
$webDisplayName = "$WorkloadName-$InstanceName-web"
$apiApp = Get-ManagedApplication `
    -StateSection $externalIdState `
    -StatePropertyName "apiApplicationObjectId" `
    -DisplayName $apiDisplayName `
    -LegacyDisplayName "$WorkloadName-api"
$webApp = Get-ManagedApplication `
    -StateSection $externalIdState `
    -StatePropertyName "webApplicationObjectId" `
    -DisplayName $webDisplayName `
    -LegacyDisplayName "$WorkloadName-web"

if ($null -eq $apiApp) {
    $apiApp = New-ManagedApplication -DisplayName $apiDisplayName
}

if ($null -eq $webApp) {
    $webApp = New-ManagedApplication -DisplayName $webDisplayName
}

if ($null -eq $apiApp -or $null -eq $webApp) {
    Write-Host "Applications do not yet exist. Dependent manifest operations are omitted from this WhatIf run."
    return
}

$apiRoles = Get-ApplicationRoles -Application $apiApp
$webRoles = Get-ApplicationRoles -Application $webApp
$apiConfig = Set-ApiApplicationConfiguration -Application $apiApp -Roles $apiRoles
Set-WebApplicationConfiguration -WebApplication $webApp `
    -ApiApplication $apiApp `
    -ApiScopeId $apiConfig.ScopeId `
    -Roles $webRoles `
    -RedirectUris $normalizedRedirectUris

Write-Host "Authoritative Shopping.Web redirect URIs:"
$normalizedRedirectUris | ForEach-Object { Write-Host "  $_" }
Write-Host "Authoritative app roles on Shopping.Web and Shopping.Api: Admin, Customer, CatalogManager"
Write-Host "Authoritative delegated API scope: $($apiConfig.Scope)"

$apiSp = Get-OrCreateServicePrincipal -Application $apiApp
$webSp = Get-OrCreateServicePrincipal -Application $webApp

if ($GrantAdminConsent -and $PSCmdlet.ShouldProcess($webApp.displayName, "Grant tenant-wide admin consent for Shopping.Api access_as_user")) {
    & az ad app permission admin-consent --id $webApp.appId --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "az command failed while granting admin consent to '$($webApp.appId)'."
    }
}

if (-not [string]::IsNullOrWhiteSpace($BootstrapAdminUserObjectId)) {
    if ($null -eq $apiSp -or $null -eq $webSp) {
        Write-Host "Service principals do not yet exist. Bootstrap Admin assignments are omitted from this WhatIf run."
    }
    else {
        Set-AdminRoleAssignment -UserObjectId $BootstrapAdminUserObjectId -Application $apiApp -ServicePrincipal $apiSp -Roles $apiRoles
        Set-AdminRoleAssignment -UserObjectId $BootstrapAdminUserObjectId -Application $webApp -ServicePrincipal $webSp -Roles $webRoles
    }
}

$webClientSecret = $null
$existingCredentials = @($webApp.passwordCredentials | Where-Object { $_.displayName -in @("shopping-bootstrap", "github-bootstrap") } | Sort-Object endDateTime -Descending)

if ($RotateWebClientSecret -or $existingCredentials.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($webApp.displayName, "Create a new one-year Web client secret")) {
        $webClientSecret = New-WebClientSecret -WebApplicationId $webApp.appId
        $webApp = Get-ApplicationByObjectId -ObjectId $webApp.id
        $existingCredentials = @($webApp.passwordCredentials | Where-Object { $_.displayName -eq "shopping-bootstrap" } | Sort-Object endDateTime -Descending)
    }
}
else {
    Write-Host "An existing Web client credential is retained. Its value cannot be recovered; use -RotateWebClientSecret only when GitHub needs a replacement secret."
}

$currentCredential = $existingCredentials | Select-Object -First 1
Set-ObjectPropertyValue -InputObject $externalIdState -Name "apiApplicationObjectId" -Value $apiApp.id
Set-ObjectPropertyValue -InputObject $externalIdState -Name "apiApplicationClientId" -Value $apiApp.appId
Set-ObjectPropertyValue -InputObject $externalIdState -Name "webApplicationObjectId" -Value $webApp.id
Set-ObjectPropertyValue -InputObject $externalIdState -Name "webApplicationClientId" -Value $webApp.appId
Set-ObjectPropertyValue -InputObject $externalIdState -Name "webRedirectUris" -Value $normalizedRedirectUris
Set-ObjectPropertyValue -InputObject $externalIdState -Name "apiAudience" -Value $apiConfig.Audience
Set-ObjectPropertyValue -InputObject $externalIdState -Name "apiScope" -Value $apiConfig.Scope

if ($null -ne $apiSp) {
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "apiServicePrincipalObjectId" -Value $apiSp.id
}

if ($null -ne $webSp) {
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "webServicePrincipalObjectId" -Value $webSp.id
}

if (-not [string]::IsNullOrWhiteSpace($BootstrapAdminEmail)) {
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "bootstrapAdminEmail" -Value $BootstrapAdminEmail
}

if (-not [string]::IsNullOrWhiteSpace($BootstrapAdminUserObjectId)) {
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "bootstrapAdminUserObjectId" -Value $BootstrapAdminUserObjectId
}

if ($null -ne $currentCredential) {
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "webClientCredentialKeyId" -Value $currentCredential.keyId
    Set-ObjectPropertyValue -InputObject $externalIdState -Name "webClientCredentialExpiresUtc" -Value $currentCredential.endDateTime
}

if ($PSCmdlet.ShouldProcess($StatePath, "Write non-secret bootstrap state")) {
    Save-BootstrapState -State $state -Path $StatePath
}

$result = [pscustomobject]@{
    TenantId = $TenantId
    Domain = $ExternalIdDomain
    Instance = $ExternalIdInstance
    ApiApplicationClientId = $apiApp.appId
    ApiAudience = $apiConfig.Audience
    ApiScope = $apiConfig.Scope
    WebApplicationClientId = $webApp.appId
    WebClientSecret = $webClientSecret
    WebClientCredentialExpiresUtc = Get-ObjectPropertyValue -InputObject $currentCredential -Name "endDateTime"
    BootstrapAdminEmail = $BootstrapAdminEmail
    BootstrapAdminUserObjectId = $BootstrapAdminUserObjectId
}

Write-Host "Entra application bootstrap completed. The state file contains identifiers only, never credential values."

if (-not $GrantAdminConsent) {
    Write-Host "Admin consent was not changed. Pass -GrantAdminConsent or grant it manually."
}

if ([string]::IsNullOrWhiteSpace($BootstrapAdminUserObjectId)) {
    Write-Host "No Bootstrap Admin assignment was requested. Use -PromptForExternalIdValues with Initialize-ShoppingBootstrap.ps1 to create or adopt the initial administrator."
}
else {
    Write-Host "Bootstrap Admin '$BootstrapAdminUserObjectId' is assigned to the Web and API Admin roles."
}

if ($PassThru) {
    $result
}
