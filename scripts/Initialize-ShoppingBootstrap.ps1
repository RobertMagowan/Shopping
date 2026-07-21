[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [ValidateSet("All", "AzureIdentity", "ExternalId", "GitHub")]
    [string]$Stage = "All",

    [string]$StatePath = ".\scripts\bootstrap-state.local.json",

    [Security.SecureString]$SqlAdministratorPassword,

    [switch]$RotateWebClientSecret,

    [switch]$GrantAdminConsent,

    [switch]$ConfigureRuleset,

    [switch]$ConfigureLocalUserSecrets,

    [switch]$AllowInteractiveTenantSwitch,

    [switch]$PromptForExternalIdValues
)

. "$PSScriptRoot\bootstrap-shared.ps1"

function Assert-ConfigValue {
    param(
        [object]$Value,
        [string]$Name
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -match "^<.+>$") {
        throw "Bootstrap configuration value '$Name' is missing or still contains a placeholder."
    }
}

function Assert-WebRedirectUri {
    param([string]$RedirectUri)

    Assert-ConfigValue -Value $RedirectUri -Name "ExternalId.WebRedirectUris"
    $parsedRedirectUri = $null

    if (-not [Uri]::TryCreate($RedirectUri, [UriKind]::Absolute, [ref]$parsedRedirectUri) -or
        $parsedRedirectUri.AbsolutePath -ne "/signin-oidc") {
        throw "Redirect URI '$RedirectUri' must be absolute and end with the exact path '/signin-oidc'."
    }

    if ($parsedRedirectUri.Scheme -ne "https" -and $parsedRedirectUri.Host -notin @("localhost", "127.0.0.1")) {
        throw "Only localhost redirect URIs may use HTTP."
    }
}

function Test-MissingConfigValue {
    param([object]$Value)

    return $null -eq $Value -or
           [string]::IsNullOrWhiteSpace([string]$Value) -or
           [string]$Value -match "^<.+>$"
}

function Read-RequiredExternalIdValue {
    param(
        [object]$CurrentValue,
        [string]$Prompt
    )

    if (-not (Test-MissingConfigValue -Value $CurrentValue)) {
        return [string]$CurrentValue
    }

    $value = Read-Host $Prompt

    if (Test-MissingConfigValue -Value $value) {
        throw "A value is required for '$Prompt'."
    }

    return $value.Trim()
}

function Select-BootstrapAdminUser {
    param([string]$CurrentUserObjectId)

    if (-not [string]::IsNullOrWhiteSpace($CurrentUserObjectId)) {
        $keepCurrent = Read-Host "Bootstrap Admin is '$CurrentUserObjectId'. Press Enter to keep it, or type 'change'"

        if ([string]::IsNullOrWhiteSpace($keepCurrent)) {
            return $CurrentUserObjectId
        }
    }

    $users = @()

    try {
        $response = Invoke-AzRestJson `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,identities"
        $users = @($response.value | Sort-Object displayName, userPrincipalName)
    }
    catch {
        Write-Warning "Microsoft Graph could not list External ID users: $($_.Exception.Message)"
    }

    if ($users.Count -gt 0) {
        Write-Host "External ID users:"

        for ($index = 0; $index -lt $users.Count; $index++) {
            $user = $users[$index]
            $signInIdentifiers = @(
                $user.identities |
                    ForEach-Object { $_.issuerAssignedId } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    Sort-Object -Unique
            )
            $signIn = if ($signInIdentifiers.Count -gt 0) {
                $signInIdentifiers -join ", "
            }
            else {
                $user.userPrincipalName
            }

            Write-Host ("  [{0}] {1} | {2} | {3}" -f ($index + 1), $user.displayName, $signIn, $user.id)
        }
    }

    while ($true) {
        $selection = Read-Host "Select the bootstrap Admin number, paste a user object ID, or press Enter to skip"

        if ([string]::IsNullOrWhiteSpace($selection)) {
            return ""
        }

        $selectedIndex = 0

        if ([int]::TryParse($selection, [ref]$selectedIndex) -and
            $selectedIndex -ge 1 -and
            $selectedIndex -le $users.Count) {
            return [string]$users[$selectedIndex - 1].id
        }

        $userObjectId = [Guid]::Empty

        if ([Guid]::TryParse($selection, [ref]$userObjectId)) {
            return $userObjectId.ToString()
        }

        Write-Warning "Enter a listed number, a valid GUID user object ID, or press Enter."
    }
}

function Test-GitHubEnvironmentSecret {
    param(
        [string]$Repository,
        [string]$EnvironmentName,
        [string]$Name
    )

    $secretNames = & gh secret list --repo $Repository --env $EnvironmentName --json name --jq ".[].name"

    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return @($secretNames) -contains $Name
}

function Set-ProjectUserSecrets {
    param(
        [string]$ProjectPath,
        [hashtable]$Values
    )

    [xml]$project = Get-Content -Raw -LiteralPath $ProjectPath
    $userSecretsId = [string]$project.Project.PropertyGroup.UserSecretsId | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($userSecretsId)) {
        throw "Project '$ProjectPath' does not define UserSecretsId."
    }

    $secretsDirectory = Join-Path $env:APPDATA "Microsoft\UserSecrets\$userSecretsId"
    $secretsPath = Join-Path $secretsDirectory "secrets.json"
    $secrets = if (Test-Path -LiteralPath $secretsPath) {
        Get-Content -Raw -LiteralPath $secretsPath | ConvertFrom-Json
    }
    else {
        [pscustomobject]@{}
    }

    foreach ($name in $Values.Keys) {
        if ($null -ne $Values[$name]) {
            Set-ObjectPropertyValue -InputObject $secrets -Name $name -Value $Values[$name]
        }
    }

    if ($PSCmdlet.ShouldProcess($secretsPath, "Write .NET user-secrets for '$ProjectPath'")) {
        New-Item -ItemType Directory -Path $secretsDirectory -Force | Out-Null
        $secrets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $secretsPath -Encoding UTF8
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Bootstrap configuration '$ConfigPath' does not exist. Copy scripts/bootstrap.config.example.psd1 and replace every placeholder."
}

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath

if ($PromptForExternalIdValues -and $Stage -in @("All", "ExternalId")) {
    $config.ExternalId.TenantId = Read-RequiredExternalIdValue `
        -CurrentValue $config.ExternalId.TenantId `
        -Prompt "External ID tenant ID"
    $config.ExternalId.Domain = Read-RequiredExternalIdValue `
        -CurrentValue $config.ExternalId.Domain `
        -Prompt "External ID primary domain (for example contoso.onmicrosoft.com)"
    $config.ExternalId.Instance = Read-RequiredExternalIdValue `
        -CurrentValue $config.ExternalId.Instance `
        -Prompt "External ID authority (for example https://contoso.ciamlogin.com/)"
}

Assert-ConfigValue -Value $config.Repository -Name "Repository"
Assert-ConfigValue -Value $config.Branch -Name "Branch"
Assert-ConfigValue -Value $config.WorkloadName -Name "WorkloadName"
Assert-ConfigValue -Value $config.Azure.TenantId -Name "Azure.TenantId"
Assert-ConfigValue -Value $config.Azure.SubscriptionId -Name "Azure.SubscriptionId"
Assert-ConfigValue -Value $config.ExternalId.TenantId -Name "ExternalId.TenantId"
Assert-ConfigValue -Value $config.ExternalId.Domain -Name "ExternalId.Domain"
Assert-ConfigValue -Value $config.ExternalId.Instance -Name "ExternalId.Instance"
Assert-ConfigValue -Value $config.GitHub.RulesetName -Name "GitHub.RulesetName"
Assert-ConfigValue -Value $config.SqlAdministratorLogin -Name "SqlAdministratorLogin"

if (@($config.Environments).Count -eq 0) {
    throw "Configure at least one deployment environment."
}

if (@($config.Azure.DeploymentRoles).Count -eq 0) {
    throw "Configure at least one Azure deployment role."
}

if (@($config.GitHub.ProductionReviewers).Count -eq 0) {
    throw "Configure at least one production reviewer."
}

foreach ($reviewer in $config.GitHub.ProductionReviewers) {
    Assert-ConfigValue -Value $reviewer -Name "GitHub.ProductionReviewers"
}

if (@($config.ExternalId.WebRedirectUris).Count -eq 0) {
    throw "ExternalId.WebRedirectUris must contain the complete authoritative callback URI list."
}

foreach ($redirectUri in $config.ExternalId.WebRedirectUris) {
    Assert-WebRedirectUri -RedirectUri $redirectUri
}

Assert-Command -Name "az"
Assert-Command -Name "gh"

if ($Stage -in @("All", "ExternalId", "GitHub")) {
    Assert-ExternalIdAuthority `
        -TenantId $config.ExternalId.TenantId `
        -Domain $config.ExternalId.Domain `
        -Instance $config.ExternalId.Instance
}

$canonicalRepository = Get-CanonicalGitHubRepository -Repository $config.Repository
$configuredInstanceName = [string](Get-ObjectPropertyValue -InputObject $config -Name "InstanceName")
$deploymentInstance = Get-DeploymentInstanceName `
    -ConfiguredInstanceName $configuredInstanceName `
    -CanonicalRepository $canonicalRepository

$bootstrapState = Read-BootstrapState -Path $StatePath
$rootState = Get-OrAddStateSection -State $bootstrapState -Name "bootstrap"
Assert-StateValue -StateSection $rootState -Name "repository" -ExpectedValue $canonicalRepository
Assert-StateValue -StateSection $rootState -Name "workloadName" -ExpectedValue $config.WorkloadName
Assert-StateValue -StateSection $rootState -Name "instanceName" -ExpectedValue $deploymentInstance
Assert-StateValue `
    -StateSection $rootState `
    -Name "oidcSubjectPrefix" `
    -ExpectedValue (Get-GitHubOidcSubjectPrefix -Repository $canonicalRepository)

if ($PSCmdlet.ShouldProcess($StatePath, "Checkpoint bootstrap target identity")) {
    Save-BootstrapState -State $bootstrapState -Path $StatePath
}

Write-Host "Bootstrap target:"
[pscustomobject]@{
    Repository = $canonicalRepository
    Instance = $deploymentInstance
    Branch = $config.Branch
    AzureTenant = $config.Azure.TenantId
    Subscription = $config.Azure.SubscriptionId
    ExternalIdTenant = $config.ExternalId.TenantId
    Environments = @($config.Environments) -join ", "
    StatePath = $StatePath
} | Format-List | Out-Host

$runAzureIdentity = $Stage -in @("All", "AzureIdentity")
$runExternalId = $Stage -in @("All", "ExternalId")
$runGitHub = $Stage -in @("All", "GitHub")
$webClientSecret = $null
$authoritativeWebRedirectUris = @($config.ExternalId.WebRedirectUris)
$environmentVariablesByEnvironment = @{}

foreach ($environmentName in $config.Environments) {
    $environmentVariablesByEnvironment[$environmentName] = @{
        RESOURCE_SUFFIX = Get-EnvironmentResourceSuffix `
            -SubscriptionId $config.Azure.SubscriptionId `
            -WorkloadName $config.WorkloadName `
            -InstanceName $deploymentInstance `
            -EnvironmentName $environmentName
    }
}

if ($runGitHub) {
    foreach ($reviewer in $config.GitHub.ProductionReviewers) {
        & gh api "users/$reviewer" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "GitHub production reviewer '$reviewer' cannot be resolved."
        }
    }

    if ($null -eq $SqlAdministratorPassword -and -not $WhatIfPreference) {
        foreach ($environmentName in $config.Environments) {
            if (-not (Test-GitHubEnvironmentSecret -Repository $canonicalRepository -EnvironmentName $environmentName -Name "SQL_ADMINISTRATOR_PASSWORD")) {
                throw "GitHub environment '$environmentName' has no SQL_ADMINISTRATOR_PASSWORD. Pass -SqlAdministratorPassword as a SecureString before any credential is rotated."
            }
        }
    }

    if ($ConfigureRuleset) {
        foreach ($workflowFile in @("ci.yml", "infra.yml", "codeql.yml")) {
            & gh api "repos/$canonicalRepository/contents/.github/workflows/$workflowFile`?ref=$($config.Branch)" | Out-Null

            if ($LASTEXITCODE -ne 0) {
                throw "Required workflow '.github/workflows/$workflowFile' does not exist on '$($config.Branch)'. Enable branch protection only after the workflows are pushed."
            }
        }
    }
}

if ($runAzureIdentity) {
    Write-Host "Starting Azure identity stage."

    $parameters = @{
        Repository = $canonicalRepository
        WorkloadName = $config.WorkloadName
        InstanceName = $deploymentInstance
        Environments = @($config.Environments)
        TenantId = $config.Azure.TenantId
        SubscriptionId = $config.Azure.SubscriptionId
        DeploymentRoles = @($config.Azure.DeploymentRoles)
        StatePath = $StatePath
        PassThru = $true
        WhatIf = $WhatIfPreference
    }

    try {
        & "$PSScriptRoot\bootstrap-github-azure-identity.ps1" @parameters | Out-Null
    }
    catch {
        throw "Azure identity stage failed: $($_.Exception.Message)"
    }

    Write-Host "Azure identity stage completed."
}

if ($runExternalId) {
    Write-Host "Starting External ID stage."

    $publicWebBaseUrls = Get-ObjectPropertyValue `
        -InputObject $config.ExternalId `
        -Name "PublicWebBaseUrls"
    $authoritativeWebRedirectUris = Get-AuthoritativeWebRedirectUris `
        -ConfiguredRedirectUris @($config.ExternalId.WebRedirectUris) `
        -SubscriptionId $config.Azure.SubscriptionId `
        -WorkloadName $config.WorkloadName `
        -InstanceName $deploymentInstance `
        -Environments @($config.Environments) `
        -PublicWebBaseUrls $publicWebBaseUrls

    foreach ($redirectUri in $authoritativeWebRedirectUris) {
        Assert-WebRedirectUri -RedirectUri $redirectUri
    }

    $currentTenantId = & az account show --query tenantId -o tsv --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the current Azure CLI tenant. Sign in before running the ExternalId stage."
    }

    if ($currentTenantId -ne $config.ExternalId.TenantId) {
        if (-not $AllowInteractiveTenantSwitch) {
            throw "External ID uses tenant '$($config.ExternalId.TenantId)', but Azure CLI is using '$currentTenantId'. Rerun with -AllowInteractiveTenantSwitch or sign in to the External ID tenant first."
        }

        Write-Host "Opening interactive sign-in for External ID tenant '$($config.ExternalId.TenantId)'."
        & az login --tenant $config.ExternalId.TenantId --allow-no-subscriptions --only-show-errors | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Interactive sign-in to External ID tenant '$($config.ExternalId.TenantId)' failed."
        }
    }

    $bootstrapState = Read-BootstrapState -Path $StatePath
    $externalIdState = Get-ObjectPropertyValue -InputObject $bootstrapState -Name "externalId"
    $bootstrapAdminUserObjectId = [string]$config.ExternalId.BootstrapAdminUserObjectId

    if ([string]::IsNullOrWhiteSpace($bootstrapAdminUserObjectId)) {
        $bootstrapAdminUserObjectId = [string](Get-ObjectPropertyValue `
            -InputObject $externalIdState `
            -Name "bootstrapAdminUserObjectId")
    }

    if ($PromptForExternalIdValues) {
        $bootstrapAdminUserObjectId = Select-BootstrapAdminUser `
            -CurrentUserObjectId $bootstrapAdminUserObjectId
    }

    $parameters = @{
        WorkloadName = $config.WorkloadName
        InstanceName = $deploymentInstance
        TenantId = $config.ExternalId.TenantId
        ExternalIdInstance = $config.ExternalId.Instance
        ExternalIdDomain = $config.ExternalId.Domain
        WebRedirectUris = $authoritativeWebRedirectUris
        StatePath = $StatePath
        RotateWebClientSecret = $RotateWebClientSecret
        GrantAdminConsent = $GrantAdminConsent
        BootstrapAdminUserObjectId = $bootstrapAdminUserObjectId
        PassThru = $true
        WhatIf = $WhatIfPreference
    }

    try {
        $entraResult = & "$PSScriptRoot\bootstrap-entra-apps.ps1" @parameters
    }
    catch {
        throw "External ID stage failed: $($_.Exception.Message)"
    }

    if ($null -ne $entraResult) {
        $webClientSecret = $entraResult.WebClientSecret
    }

    if ($null -ne $webClientSecret -and -not $runGitHub) {
        Write-Warning "A new Web client secret was issued but the GitHub stage is not part of this run. The value will not be recoverable after this process exits. Use Stage All when rotating a credential that GitHub must receive."
    }

    if ($ConfigureLocalUserSecrets -and $null -ne $entraResult) {
        $webSecretValue = ConvertFrom-SecureStringValue -SecureValue $webClientSecret

        try {
            Set-ProjectUserSecrets -ProjectPath (Join-Path $PSScriptRoot "..\src\Shopping.Web\Shopping.Web.csproj") -Values @{
                "EntraExternalId:Instance" = $entraResult.Instance
                "EntraExternalId:Domain" = $entraResult.Domain
                "EntraExternalId:TenantId" = $entraResult.TenantId
                "EntraExternalId:ClientId" = $entraResult.WebApplicationClientId
                "EntraExternalId:ClientSecret" = $webSecretValue
                "ShoppingApi:Scopes:0" = $entraResult.ApiScope
            }
            Set-ProjectUserSecrets -ProjectPath (Join-Path $PSScriptRoot "..\src\Shopping.Api\Shopping.Api.csproj") -Values @{
                "EntraExternalId:Instance" = $entraResult.Instance
                "EntraExternalId:TenantId" = $entraResult.TenantId
                "EntraExternalId:ClientId" = $entraResult.ApiApplicationClientId
                "EntraExternalId:Audience" = $entraResult.ApiAudience
            }
        }
        finally {
            $webSecretValue = $null
        }

        if ($null -eq $webClientSecret) {
            Write-Host "Existing local Web client secret was preserved because Entra did not issue a replacement."
        }
    }

    Write-Host "External ID stage completed."
}

if ($runGitHub) {
    Write-Host "Starting GitHub stage."

    $state = Read-BootstrapState -Path $StatePath
    $azureState = Get-ObjectPropertyValue -InputObject $state -Name "azure"
    $externalIdState = Get-ObjectPropertyValue -InputObject $state -Name "externalId"

    if ($null -eq $azureState -or $null -eq $externalIdState) {
        throw "Bootstrap state is incomplete. Run the AzureIdentity and ExternalId stages before the GitHub stage."
    }

    $environmentVariables = @{
        AZURE_CLIENT_ID = $azureState.deploymentApplicationClientId
        AZURE_PRINCIPAL_OBJECT_ID = $azureState.deploymentServicePrincipalObjectId
        AZURE_TENANT_ID = $azureState.tenantId
        AZURE_SUBSCRIPTION_ID = $azureState.subscriptionId
        WORKLOAD_NAME = $config.WorkloadName
        DEPLOYMENT_INSTANCE = $deploymentInstance
        SQL_ADMINISTRATOR_LOGIN = $config.SqlAdministratorLogin
        ENTRA_EXTERNAL_ID_INSTANCE = $externalIdState.instance
        ENTRA_EXTERNAL_ID_DOMAIN = $externalIdState.domain
        ENTRA_EXTERNAL_ID_TENANT_ID = $externalIdState.tenantId
        ENTRA_EXTERNAL_ID_WEB_CLIENT_ID = $externalIdState.webApplicationClientId
        ENTRA_EXTERNAL_ID_API_CLIENT_ID = $externalIdState.apiApplicationClientId
        ENTRA_EXTERNAL_ID_API_AUDIENCE = $externalIdState.apiAudience
        SHOPPING_API_SCOPE = $externalIdState.apiScope
    }

    $environmentSecrets = @{}

    if ($null -ne $SqlAdministratorPassword) {
        $environmentSecrets.SQL_ADMINISTRATOR_PASSWORD = $SqlAdministratorPassword
    }

    if ($null -ne $webClientSecret) {
        $environmentSecrets.ENTRA_EXTERNAL_ID_WEB_CLIENT_SECRET = $webClientSecret
    }

    if (-not $WhatIfPreference) {
        foreach ($environmentName in $config.Environments) {
            if ($null -eq $SqlAdministratorPassword -and -not (Test-GitHubEnvironmentSecret -Repository $canonicalRepository -EnvironmentName $environmentName -Name "SQL_ADMINISTRATOR_PASSWORD")) {
                throw "GitHub environment '$environmentName' has no SQL_ADMINISTRATOR_PASSWORD. Pass -SqlAdministratorPassword as a SecureString."
            }

            if ($null -eq $webClientSecret -and -not (Test-GitHubEnvironmentSecret -Repository $canonicalRepository -EnvironmentName $environmentName -Name "ENTRA_EXTERNAL_ID_WEB_CLIENT_SECRET")) {
                throw "GitHub environment '$environmentName' has no Web client secret. Rerun the ExternalId stage with -RotateWebClientSecret."
            }
        }
    }

    $parameters = @{
        Repository = $canonicalRepository
        Branch = $config.Branch
        InstanceName = $deploymentInstance
        Environments = @($config.Environments)
        ProdReviewerUsers = @($config.GitHub.ProductionReviewers)
        EnvironmentVariables = $environmentVariables
        EnvironmentVariablesByEnvironment = $environmentVariablesByEnvironment
        EnvironmentSecrets = $environmentSecrets
        StatePath = $StatePath
        RulesetName = $config.GitHub.RulesetName
        ConfigureRuleset = $ConfigureRuleset
        WhatIf = $WhatIfPreference
    }

    try {
        & "$PSScriptRoot\bootstrap-github.ps1" @parameters
    }
    catch {
        throw "GitHub stage failed: $($_.Exception.Message)"
    }

    Write-Host "GitHub stage completed."
}

Write-Host "Bootstrap stage '$Stage' completed. Run Test-ShoppingBootstrap.ps1 to verify the resulting configuration."
