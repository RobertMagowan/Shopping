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

Write-Host "Bootstrap shared helper tests passed."
