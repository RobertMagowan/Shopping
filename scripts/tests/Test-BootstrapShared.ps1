$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$bootstrapSharedPath = Join-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -ChildPath "bootstrap-shared.ps1"

. $bootstrapSharedPath

$expectedUrl = "https://shop.example.test"
$configuration = @{
    dev = $expectedUrl
}

$actualUrl = Get-ObjectPropertyValue `
    -InputObject $configuration `
    -Name "dev"

if ($actualUrl -ne $expectedUrl) {
    throw "Expected hashtable value '$expectedUrl', but found '$actualUrl'."
}

Set-ObjectPropertyValue `
    -InputObject $configuration `
    -Name "test" `
    -Value "https://test.example.test"

if ($configuration["test"] -ne "https://test.example.test") {
    throw "Expected Set-ObjectPropertyValue to add the hashtable key."
}

$objectValue = [pscustomobject]@{
    Name = "Shopping"
}

if ((Get-ObjectPropertyValue -InputObject $objectValue -Name "Name") -ne "Shopping") {
    throw "Expected object property lookup to remain supported."
}

Set-ObjectPropertyValue `
    -InputObject $objectValue `
    -Name "Name" `
    -Value "Shopping Updated"

if ((Get-ObjectPropertyValue -InputObject $objectValue -Name "Name") -ne "Shopping Updated") {
    throw "Expected existing object property updates to remain supported."
}

Set-ObjectPropertyValue `
    -InputObject $objectValue `
    -Name "DisplayName" `
    -Value "Shop"

if ((Get-ObjectPropertyValue -InputObject $objectValue -Name "DisplayName") -ne "Shop") {
    throw "Expected new object property creation to remain supported."
}

$requiredProviders = @(Get-RequiredAzureResourceProviders)

foreach ($providerNamespace in @("Microsoft.AlertsManagement", "Microsoft.Insights")) {
    if ($requiredProviders -notcontains $providerNamespace) {
        throw "Expected required Azure resource provider '$providerNamespace'."
    }
}

$defaultAzureConfiguration = @{}

if ((Get-EnvironmentManagedRedisLocation `
        -AzureConfiguration $defaultAzureConfiguration `
        -EnvironmentName "prod" `
        -DefaultLocation "uksouth") -ne "uksouth") {
    throw "Expected Managed Redis to use the application region by default."
}

if (-not (Get-EnvironmentSqlZoneRedundant `
        -AzureConfiguration $defaultAzureConfiguration `
        -EnvironmentName "prod")) {
    throw "Expected production SQL zone redundancy to default to enabled."
}

$overriddenAzureConfiguration = @{
    ManagedRedisLocations = @{
        prod = "ukwest"
    }
    SqlZoneRedundancy = @{
        prod = $false
    }
}

if ((Get-EnvironmentManagedRedisLocation `
        -AzureConfiguration $overriddenAzureConfiguration `
        -EnvironmentName "prod" `
        -DefaultLocation "uksouth") -ne "ukwest") {
    throw "Expected the production Managed Redis location override."
}

if (Get-EnvironmentSqlZoneRedundant `
        -AzureConfiguration $overriddenAzureConfiguration `
        -EnvironmentName "prod") {
    throw "Expected the production SQL zone-redundancy override."
}

Write-Host "Bootstrap shared helper tests passed."
