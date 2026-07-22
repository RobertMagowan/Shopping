Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it before running this script."
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments)

    $json = & az @Arguments --only-show-errors -o json

    if ($LASTEXITCODE -ne 0) {
        throw "az command failed: az $($Arguments -join ' ')"
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json
}

function Invoke-AzTsv {
    param([string[]]$Arguments)

    $result = & az @Arguments --only-show-errors -o tsv

    if ($LASTEXITCODE -ne 0) {
        throw "az command failed: az $($Arguments -join ' ')"
    }

    return $result
}

function Invoke-AzRestJson {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body
    )

    $tempFile = $null

    try {
        if ($null -eq $Body) {
            $result = & az rest --method $Method --uri $Uri --only-show-errors -o json
        }
        else {
            $tempFile = New-TemporaryFile
            $json = $Body | ConvertTo-Json -Depth 50
            $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($tempFile.FullName, $json, $utf8WithoutBom)
            $result = & az rest --method $Method --uri $Uri --headers "Content-Type=application/json" --body "@$($tempFile.FullName)" --only-show-errors -o json
        }

        if ($LASTEXITCODE -ne 0) {
            throw "az rest failed: $Method $Uri"
        }

        if ([string]::IsNullOrWhiteSpace($result)) {
            return $null
        }

        return $result | ConvertFrom-Json
    }
    finally {
        if ($null -ne $tempFile) {
            Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-DeterministicGuid {
    param([string]$Value)

    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = $md5.ComputeHash($bytes)

    return [Guid]::new($hash)
}

function Get-ApplicationByDisplayName {
    param([string]$DisplayName)

    $apps = Invoke-AzJson -Arguments @("ad", "app", "list", "--display-name", $DisplayName)

    $matchingApps = @($apps | Where-Object { $_.displayName -eq $DisplayName })

    if ($matchingApps.Count -eq 0) {
        return $null
    }

    if ($matchingApps.Count -gt 1) {
        throw "More than one application named '$DisplayName' exists. Record the intended application object ID in the bootstrap state before continuing."
    }

    return $matchingApps[0]
}

function Get-ApplicationByObjectId {
    param([string]$ObjectId)

    if ([string]::IsNullOrWhiteSpace($ObjectId)) {
        return $null
    }

    Invoke-AzJson -Arguments @("ad", "app", "show", "--id", $ObjectId)
}

function Ensure-Application {
    param(
        [string]$DisplayName,
        [string]$SignInAudience = "AzureADMyOrg"
    )

    $app = Get-ApplicationByDisplayName -DisplayName $DisplayName

    if ($null -ne $app) {
        return $app
    }

    Invoke-AzJson -Arguments @("ad", "app", "create", "--display-name", $DisplayName, "--sign-in-audience", $SignInAudience)
}

function Ensure-ServicePrincipal {
    param([string]$AppId)

    $servicePrincipal = Get-ServicePrincipalByAppId -AppId $AppId

    if ($null -ne $servicePrincipal) {
        return $servicePrincipal
    }

    Invoke-AzJson -Arguments @("ad", "sp", "create", "--id", $AppId)
}

function Get-ServicePrincipalByAppId {
    param([string]$AppId)

    $servicePrincipals = Invoke-AzJson -Arguments @("ad", "sp", "list", "--filter", "appId eq '$AppId'")
    $matchingServicePrincipals = @($servicePrincipals | Where-Object { $_.appId -eq $AppId })

    if ($matchingServicePrincipals.Count -gt 1) {
        throw "More than one service principal exists for application ID '$AppId'."
    }

    if ($matchingServicePrincipals.Count -eq 0) {
        return $null
    }

    return $matchingServicePrincipals[0]
}

function Test-ObjectProperty {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Name)
    }

    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-ObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if (-not (Test-ObjectProperty -InputObject $InputObject -Name $Name)) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject[$Name]
    }

    return $InputObject.PSObject.Properties[$Name].Value
}

function Set-ObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Name] = $Value
        return
    }

    if (Test-ObjectProperty -InputObject $InputObject -Name $Name) {
        $InputObject.PSObject.Properties[$Name].Value = $Value
        return
    }

    $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
}

function Assert-AzureContext {
    param(
        [string]$TenantId,
        [string]$SubscriptionId
    )

    Invoke-AzJson -Arguments @("account", "set", "--subscription", $SubscriptionId) | Out-Null
    $account = Invoke-AzJson -Arguments @("account", "show")

    if ($account.tenantId -ne $TenantId) {
        throw "Azure CLI is signed in to tenant '$($account.tenantId)', but '$TenantId' was requested. Run 'az login --tenant $TenantId'."
    }
}

function Assert-EntraContext {
    param([string]$TenantId)

    $account = Invoke-AzJson -Arguments @("account", "show")

    if ($account.tenantId -ne $TenantId) {
        throw "Azure CLI is using tenant '$($account.tenantId)', but External ID tenant '$TenantId' was requested. Run 'az login --tenant $TenantId --allow-no-subscriptions'."
    }
}

function Assert-ExternalIdAuthority {
    param(
        [string]$TenantId,
        [string]$Domain,
        [string]$Instance
    )

    $parsedTenantId = [Guid]::Empty

    if (-not [Guid]::TryParse($TenantId, [ref]$parsedTenantId)) {
        throw "External ID tenant ID '$TenantId' is not a valid GUID."
    }

    $normalizedTenantId = $parsedTenantId.ToString()
    $domainMatch = [Regex]::Match($Domain.Trim(),
                                 "^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)\.onmicrosoft\.com$",
                                 [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if (-not $domainMatch.Success) {
        throw "External ID domain '$Domain' must be the tenant's primary '<name>.onmicrosoft.com' domain."
    }

    $instanceUri = $null

    if (-not [Uri]::TryCreate($Instance, [UriKind]::Absolute, [ref]$instanceUri) -or
        $instanceUri.Scheme -ne "https" -or
        $instanceUri.AbsolutePath -ne "/" -or
        -not [string]::IsNullOrWhiteSpace($instanceUri.Query) -or
        -not [string]::IsNullOrWhiteSpace($instanceUri.Fragment)) {
        throw "External ID instance '$Instance' must be an HTTPS origin ending in '/', without a path, query string, or fragment."
    }

    $expectedInstanceHost = "$($domainMatch.Groups[1].Value.ToLowerInvariant()).ciamlogin.com"

    if ($instanceUri.Host -cne $expectedInstanceHost) {
        throw "External ID instance host '$($instanceUri.Host)' does not match domain '$Domain'. Expected '$expectedInstanceHost'."
    }

    $metadataUri = "$($instanceUri.GetLeftPart([UriPartial]::Authority))/$normalizedTenantId/v2.0/.well-known/openid-configuration"

    try {
        $metadata = Invoke-RestMethod -Method Get -Uri $metadataUri -TimeoutSec 30 -ErrorAction Stop
    }
    catch {
        throw "External ID metadata could not be loaded from '$metadataUri'. Verify that ExternalId.TenantId is the tenant ID shown on the '$Domain' External ID overview, not the Azure subscription's home tenant ID. $($_.Exception.Message)"
    }

    $issuerUri = $null
    $authorizationEndpointUri = $null

    if (-not [Uri]::TryCreate([string]$metadata.issuer, [UriKind]::Absolute, [ref]$issuerUri) -or
        $issuerUri.Host -cne "$normalizedTenantId.ciamlogin.com" -or
        $issuerUri.AbsolutePath.Trim("/") -cne "$normalizedTenantId/v2.0") {
        throw "External ID metadata issuer '$($metadata.issuer)' does not match configured tenant '$normalizedTenantId'."
    }

    if (-not [Uri]::TryCreate([string]$metadata.authorization_endpoint,
                              [UriKind]::Absolute,
                              [ref]$authorizationEndpointUri) -or
        $authorizationEndpointUri.Host -cne $expectedInstanceHost) {
        throw "External ID authorization endpoint '$($metadata.authorization_endpoint)' does not match configured instance '$Instance'."
    }
}

function Get-CanonicalGitHubRepository {
    param([string]$Repository)

    Assert-Command -Name "gh"
    $canonicalRepository = & gh repo view $Repository --json nameWithOwner --jq ".nameWithOwner"

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($canonicalRepository)) {
        throw "Unable to resolve GitHub repository '$Repository'. Authenticate with 'gh auth login' and verify repository access."
    }

    return $canonicalRepository.Trim()
}

function Get-GitHubOidcSubjectPrefix {
    param([string]$Repository)

    $canonicalRepository = Get-CanonicalGitHubRepository -Repository $Repository
    $oidcConfiguration = & gh api "repos/$canonicalRepository/actions/oidc/customization/sub" | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read GitHub OIDC subject configuration for '$canonicalRepository'."
    }

    $subjectPrefix = Get-ObjectPropertyValue -InputObject $oidcConfiguration -Name "sub_claim_prefix"

    if ([string]::IsNullOrWhiteSpace([string]$subjectPrefix)) {
        throw "GitHub did not return an OIDC subject prefix for '$canonicalRepository'."
    }

    return $subjectPrefix
}

function Get-GitHubOidcIssuer {
    return "https://token.actions.githubusercontent.com"
}

function Get-GitHubOidcAudience {
    return "api://AzureADTokenExchange"
}

function Get-RequiredAzureResourceProviders {
    return @(
        "Microsoft.AlertsManagement",
        "Microsoft.Authorization",
        "Microsoft.App",
        "Microsoft.Cache",
        "Microsoft.Cdn",
        "Microsoft.ContainerRegistry",
        "Microsoft.Insights",
        "Microsoft.KeyVault",
        "Microsoft.ManagedIdentity",
        "Microsoft.Network",
        "Microsoft.OperationalInsights",
        "Microsoft.Resources",
        "Microsoft.Sql",
        "Microsoft.Storage"
    )
}

function ConvertTo-WebRedirectUri {
    param(
        [string]$BaseUrl,
        [string]$Source
    )

    $parsedBaseUrl = $null

    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$parsedBaseUrl) -or
        $parsedBaseUrl.Scheme -ne "https" -or
        -not [string]::IsNullOrWhiteSpace($parsedBaseUrl.Query) -or
        -not [string]::IsNullOrWhiteSpace($parsedBaseUrl.Fragment) -or
        $parsedBaseUrl.AbsolutePath -ne "/") {
        throw "$Source '$BaseUrl' must be an HTTPS origin without a path, query string, or fragment."
    }

    return "$($parsedBaseUrl.GetLeftPart([UriPartial]::Authority))/signin-oidc"
}

function Get-StableHashFragment {
    param(
        [string]$Value,
        [int]$Length = 8
    )

    $sha256 = [Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        $hex = [BitConverter]::ToString($hash).Replace("-", "")
        return $hex.Substring(0, $Length).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-DeploymentInstanceName {
    param(
        [string]$ConfiguredInstanceName,
        [string]$CanonicalRepository
    )

    $source = if ([string]::IsNullOrWhiteSpace($ConfiguredInstanceName) -or
                  $ConfiguredInstanceName -match "^<.+>$") {
        $CanonicalRepository.Replace("/", "-")
    }
    else {
        $ConfiguredInstanceName
    }

    $normalized = $source.ToLowerInvariant() -replace "[^a-z0-9-]", "-"
    $normalized = ($normalized -replace "-+", "-").Trim("-")

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Deployment InstanceName '$source' does not contain any Azure-safe letters or numbers."
    }

    if ($normalized.Length -gt 24) {
        $hash = Get-StableHashFragment -Value $source.ToLowerInvariant()
        $normalized = "$($normalized.Substring(0, 15).TrimEnd('-'))-$hash"
    }

    if ($normalized.Length -lt 2) {
        $normalized = "i-$normalized"
    }

    return $normalized
}

function Get-EnvironmentResourceSuffix {
    param(
        [string]$SubscriptionId,
        [string]$WorkloadName,
        [string]$InstanceName,
        [string]$EnvironmentName
    )

    $inputValue = "$($SubscriptionId.ToLowerInvariant())|$($WorkloadName.ToLowerInvariant())|$($InstanceName.ToLowerInvariant())|$($EnvironmentName.ToLowerInvariant())"
    return Get-StableHashFragment -Value $inputValue
}

function Get-AuthoritativeWebRedirectUris {
    param(
        [string[]]$ConfiguredRedirectUris,
        [string]$SubscriptionId,
        [string]$WorkloadName,
        [string]$InstanceName,
        [string[]]$Environments,
        [object]$PublicWebBaseUrls
    )

    $deployedRedirectUris = foreach ($environmentName in $Environments) {
        $configuredBaseUrl = [string](Get-ObjectPropertyValue `
            -InputObject $PublicWebBaseUrls `
            -Name $environmentName)

        if (-not [string]::IsNullOrWhiteSpace($configuredBaseUrl)) {
            ConvertTo-WebRedirectUri `
                -BaseUrl $configuredBaseUrl.Trim() `
                -Source "ExternalId.PublicWebBaseUrls.$environmentName"
            continue
        }

        Write-Warning "ExternalId.PublicWebBaseUrls.$environmentName is empty. Deploy the Container App, copy its Web origin from the workflow output, set this value, and rerun the ExternalId stage before testing sign-in."
    }

    return @($ConfiguredRedirectUris + $deployedRedirectUris | Sort-Object -Unique)
}

function Read-BootstrapState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            schemaVersion = 1
        }
    }

    $state = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json

    if ($state.schemaVersion -ne 1) {
        throw "Bootstrap state '$Path' uses unsupported schema version '$($state.schemaVersion)'."
    }

    return $state
}

function Save-BootstrapState {
    param(
        [object]$State,
        [string]$Path
    )

    $outputDirectory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }

    $State | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-OrAddStateSection {
    param(
        [object]$State,
        [string]$Name
    )

    if (-not (Test-ObjectProperty -InputObject $State -Name $Name)) {
        Set-ObjectPropertyValue -InputObject $State -Name $Name -Value ([pscustomobject]@{})
    }

    return Get-ObjectPropertyValue -InputObject $State -Name $Name
}

function Assert-StateValue {
    param(
        [object]$StateSection,
        [string]$Name,
        [string]$ExpectedValue
    )

    $currentValue = Get-ObjectPropertyValue -InputObject $StateSection -Name $Name

    if (-not [string]::IsNullOrWhiteSpace([string]$currentValue) -and $currentValue -ne $ExpectedValue) {
        throw "Bootstrap state value '$Name' is '$currentValue', but '$ExpectedValue' was requested. Use the correct state file or deliberately create a new one."
    }

    Set-ObjectPropertyValue -InputObject $StateSection -Name $Name -Value $ExpectedValue
}

function Get-RequiredGitHubStatusChecks {
    return @(
        "ci-build",
        "ci-test",
        "container-build",
        "infra-static-validation-dev",
        "infra-static-validation-test",
        "infra-static-validation-prod"
    )
}

function ConvertFrom-SecureStringValue {
    param([Security.SecureString]$SecureValue)

    if ($null -eq $SecureValue) {
        return $null
    }

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}
