[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [string]$WorkloadName = "shopping",

    [Parameter(Mandatory = $true)]
    [string]$InstanceName,

    [string[]]$Environments = @("dev", "test", "prod"),

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$StatePath = ".\scripts\bootstrap-state.local.json",

    [string[]]$DeploymentRoles = @(
        "Contributor",
        "Role Based Access Control Administrator"
    ),

    [switch]$PassThru
)

. "$PSScriptRoot\bootstrap-shared.ps1"

function Set-FederatedCredential {
    param(
        [string]$AppId,
        [string]$Name,
        [string]$Subject
    )

    $existing = Invoke-AzJson -Arguments @("ad", "app", "federated-credential", "list", "--id", $AppId)
    $match = @($existing | Where-Object { $_.name -eq $Name })
    $expectedIssuer = Get-GitHubOidcIssuer
    $expectedAudience = Get-GitHubOidcAudience

    if ($match.Count -gt 1) {
        throw "Application '$AppId' has duplicate federated credentials named '$Name'. Remove the duplicate before continuing."
    }

    if ($match.Count -eq 1) {
        $audiencesMatch = @(Compare-Object -ReferenceObject @($expectedAudience) -DifferenceObject @($match[0].audiences) -CaseSensitive).Count -eq 0

        if ($match[0].issuer -ceq $expectedIssuer -and
            $match[0].subject -ceq $Subject -and
            $audiencesMatch) {
            return
        }
    }

    $credential = @{
        name = $Name
        issuer = $expectedIssuer
        subject = $Subject
        description = "Shopping bootstrap: GitHub Actions OIDC for $Subject"
        audiences = @($expectedAudience)
    }

    $tempFile = New-TemporaryFile

    try {
        $json = $credential | ConvertTo-Json -Depth 10
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempFile.FullName, $json, $utf8WithoutBom)

        if ($match.Count -eq 0) {
            Invoke-AzJson -Arguments @("ad", "app", "federated-credential", "create", "--id", $AppId, "--parameters", $tempFile.FullName) | Out-Null
            return
        }

        Invoke-AzJson -Arguments @("ad", "app", "federated-credential", "update", "--id", $AppId, "--federated-credential-id", $Name, "--parameters", $tempFile.FullName) | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Set-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$RoleName,
        [string]$Scope
    )

    $existing = Invoke-AzTsv -Arguments @("role", "assignment", "list", "--assignee", $PrincipalId, "--role", $RoleName, "--scope", $Scope, "--query", "[].id")

    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return
    }

    Invoke-AzJson -Arguments @("role", "assignment", "create", "--assignee-object-id", $PrincipalId, "--assignee-principal-type", "ServicePrincipal", "--role", $RoleName, "--scope", $Scope) | Out-Null
}

Assert-Command -Name "az"
Assert-Command -Name "gh"
$canonicalRepository = Get-CanonicalGitHubRepository -Repository $Repository
$oidcSubjectPrefix = Get-GitHubOidcSubjectPrefix -Repository $canonicalRepository
Assert-AzureContext -TenantId $TenantId -SubscriptionId $SubscriptionId

$state = Read-BootstrapState -Path $StatePath
$rootState = Get-OrAddStateSection -State $state -Name "bootstrap"
Assert-StateValue -StateSection $rootState -Name "repository" -ExpectedValue $canonicalRepository
Assert-StateValue -StateSection $rootState -Name "workloadName" -ExpectedValue $WorkloadName
Assert-StateValue -StateSection $rootState -Name "instanceName" -ExpectedValue $InstanceName
Assert-StateValue -StateSection $rootState -Name "oidcSubjectPrefix" -ExpectedValue $oidcSubjectPrefix

$azureState = Get-OrAddStateSection -State $state -Name "azure"
Assert-StateValue -StateSection $azureState -Name "tenantId" -ExpectedValue $TenantId
Assert-StateValue -StateSection $azureState -Name "subscriptionId" -ExpectedValue $SubscriptionId

$applicationObjectId = Get-ObjectPropertyValue -InputObject $azureState -Name "deploymentApplicationObjectId"
$deploymentApp = Get-ApplicationByObjectId -ObjectId $applicationObjectId
$deploymentAppDisplayName = "$WorkloadName-$InstanceName-github-deploy"
$legacyDeploymentAppDisplayName = "$WorkloadName-github-deploy"

if (-not [string]::IsNullOrWhiteSpace([string]$applicationObjectId) -and $null -eq $deploymentApp) {
    throw "The deployment application recorded in '$StatePath' no longer exists. Review the state before creating or adopting another application."
}

if ($null -eq $deploymentApp) {
    $deploymentApp = Get-ApplicationByDisplayName -DisplayName $deploymentAppDisplayName
}

if ($null -eq $deploymentApp) {
    if (-not $PSCmdlet.ShouldProcess($deploymentAppDisplayName, "Create GitHub deployment application")) {
        Write-Host "No deployment application exists. Dependent OIDC and RBAC operations are omitted from this WhatIf run."
        return
    }

    $deploymentApp = Invoke-AzJson -Arguments @("ad", "app", "create", "--display-name", $deploymentAppDisplayName, "--sign-in-audience", "AzureADMyOrg")
}
elseif ($deploymentApp.displayName -ne $deploymentAppDisplayName) {
    if ($deploymentApp.displayName -eq $legacyDeploymentAppDisplayName -and
        $PSCmdlet.ShouldProcess($deploymentApp.displayName, "Rename state-pinned application to '$deploymentAppDisplayName'")) {
        Invoke-AzJson -Arguments @("ad", "app", "update", "--id", $deploymentApp.id, "--display-name", $deploymentAppDisplayName) | Out-Null
        $deploymentApp = Get-ApplicationByObjectId -ObjectId $deploymentApp.id
    }
    elseif ($deploymentApp.displayName -ne $legacyDeploymentAppDisplayName) {
        throw "State points to application '$($deploymentApp.displayName)', expected '$deploymentAppDisplayName'."
    }
}

$deploymentSp = Get-ServicePrincipalByAppId -AppId $deploymentApp.appId

if ($null -eq $deploymentSp) {
    if (-not $PSCmdlet.ShouldProcess($deploymentApp.appId, "Create deployment service principal")) {
        Write-Host "No deployment service principal exists. Dependent OIDC and RBAC operations are omitted from this WhatIf run."
        return
    }

    $deploymentSp = Ensure-ServicePrincipal -AppId $deploymentApp.appId
}
$desiredCredentials = foreach ($environmentName in $Environments) {
    [pscustomobject]@{
        Name = "github-$environmentName"
        Subject = "$oidcSubjectPrefix`:environment:$environmentName"
    }
}

Write-Host "Authoritative GitHub OIDC subjects:"
$desiredCredentials | Format-Table -AutoSize | Out-Host

foreach ($credential in $desiredCredentials) {
    if ($PSCmdlet.ShouldProcess($credential.Subject, "Create or replace federated credential '$($credential.Name)'")) {
        Set-FederatedCredential -AppId $deploymentApp.appId -Name $credential.Name -Subject $credential.Subject
    }
}

$subscriptionScope = "/subscriptions/$SubscriptionId"

foreach ($roleName in $DeploymentRoles) {
    if ($PSCmdlet.ShouldProcess("$roleName at $subscriptionScope", "Ensure deployment service-principal role assignment")) {
        Set-RoleAssignment -PrincipalId $deploymentSp.id -RoleName $roleName -Scope $subscriptionScope
    }
}

Set-ObjectPropertyValue -InputObject $azureState -Name "deploymentApplicationObjectId" -Value $deploymentApp.id
Set-ObjectPropertyValue -InputObject $azureState -Name "deploymentApplicationClientId" -Value $deploymentApp.appId
Set-ObjectPropertyValue -InputObject $azureState -Name "deploymentServicePrincipalObjectId" -Value $deploymentSp.id

if ($PSCmdlet.ShouldProcess($StatePath, "Write non-secret bootstrap state")) {
    Save-BootstrapState -State $state -Path $StatePath
}

$result = [pscustomobject]@{
    Repository = $canonicalRepository
    TenantId = $TenantId
    SubscriptionId = $SubscriptionId
    ApplicationClientId = $deploymentApp.appId
    ApplicationObjectId = $deploymentApp.id
    ServicePrincipalObjectId = $deploymentSp.id
}

Write-Host "GitHub Azure deployment identity bootstrap completed for $canonicalRepository."

if ($PassThru) {
    $result
}
