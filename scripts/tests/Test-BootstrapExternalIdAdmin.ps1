$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $scriptsRoot 'bootstrap-shared.ps1')
. (Join-Path $scriptsRoot 'bootstrap-external-id-admin.ps1')

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -cne $Expected) {
        throw "$Message Expected '$Expected', found '$Actual'."
    }
}

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$ExpectedMessage
    )

    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Expected error containing '$ExpectedMessage', found '$($_.Exception.Message)'."
        }

        return
    }

    throw "Expected an error containing '$ExpectedMessage'."
}

Assert-Equal `
    -Actual (Normalize-BootstrapAdminEmail -Email '  Admin.User@Example.COM ') `
    -Expected 'admin.user@example.com' `
    -Message 'Email normalization failed.'

Assert-Throws `
    -Action { Normalize-BootstrapAdminEmail -Email 'not-an-email' } `
    -ExpectedMessage 'valid email address'

$passwords = 1..100 | ForEach-Object { New-BootstrapAdminTemporaryPassword }

foreach ($password in $passwords) {
    if ($password.Length -ne 24 -or
        $password -cnotmatch '[A-Z]' -or
        $password -cnotmatch '[a-z]' -or
        $password -notmatch '[0-9]' -or
        $password -notmatch '[!@#$%*+\-_=]') {
        throw 'Generated password does not satisfy the bootstrap policy.'
    }
}

if (@($passwords | Sort-Object -Unique).Count -ne $passwords.Count) {
    throw 'Generated bootstrap passwords were not unique within the test sample.'
}

$script:graphUsers = @(
    [pscustomobject]@{
        id = '11111111-1111-1111-1111-111111111111'
        accountEnabled = $true
        identities = @(
            [pscustomobject]@{
                signInType = 'emailAddress'
                issuer = 'Shopping1970.onmicrosoft.com'
                issuerAssignedId = 'Admin.User@Example.com'
            }
        )
    },
    [pscustomobject]@{
        id = '22222222-2222-2222-2222-222222222222'
        accountEnabled = $true
        identities = @(
            [pscustomobject]@{
                signInType = 'userName'
                issuer = 'Shopping1970.onmicrosoft.com'
                issuerAssignedId = 'admin.user@example.com'
            }
        )
    }
)
$script:capturedCreateBody = $null
$script:createRequestCount = 0

function Invoke-AzRestJson {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body
    )

    if ($Method -eq 'GET') {
        if ($Uri -match '/users/([^?]+)') {
            $objectId = $Matches[1]
            return @($script:graphUsers | Where-Object id -eq $objectId) | Select-Object -First 1
        }

        return [pscustomobject]@{ value = $script:graphUsers }
    }

    if ($Method -eq 'POST') {
        $script:createRequestCount++
        $script:capturedCreateBody = $Body
        return [pscustomobject]@{
            id = '33333333-3333-3333-3333-333333333333'
            accountEnabled = $true
            identities = $Body.identities
        }
    }

    throw "Unexpected Graph request: $Method $Uri"
}

$matchedUser = Get-BootstrapAdminLocalUser `
    -Email 'admin.user@example.com' `
    -Domain 'shopping1970.onmicrosoft.com'

Assert-Equal `
    -Actual $matchedUser.id `
    -Expected '11111111-1111-1111-1111-111111111111' `
    -Message 'Local identity matching failed.'

$missingUser = Get-BootstrapAdminLocalUser `
    -Email 'missing@example.com' `
    -Domain 'shopping1970.onmicrosoft.com'

if ($null -ne $missingUser) {
    throw 'A missing local identity should return null.'
}

$script:graphUsers += $script:graphUsers[0].PSObject.Copy()
Assert-Throws `
    -Action {
        Get-BootstrapAdminLocalUser `
            -Email 'admin.user@example.com' `
            -Domain 'shopping1970.onmicrosoft.com'
    } `
    -ExpectedMessage 'More than one local External ID user'
$script:graphUsers = @($script:graphUsers | Select-Object -First 2)

$temporaryPassword = New-BootstrapAdminTemporaryPassword
$createdUser = New-BootstrapAdminLocalUser `
    -Email 'new.admin@example.com' `
    -Domain 'Shopping1970.onmicrosoft.com' `
    -TemporaryPassword $temporaryPassword

Assert-Equal -Actual $createdUser.id -Expected '33333333-3333-3333-3333-333333333333' -Message 'User creation result was not returned.'
Assert-Equal -Actual $script:capturedCreateBody.creationType -Expected 'LocalAccount' -Message 'Creation type is incorrect.'
Assert-Equal -Actual $script:capturedCreateBody.passwordPolicies -Expected 'DisablePasswordExpiration' -Message 'Password policy is incorrect.'
Assert-Equal -Actual $script:capturedCreateBody.passwordProfile.password -Expected $temporaryPassword -Message 'Temporary password was not sent.'
Assert-Equal -Actual $script:capturedCreateBody.passwordProfile.forceChangePasswordNextSignIn -Expected $true -Message 'First-login password change is not required.'
Assert-Equal -Actual $script:capturedCreateBody.identities[0].issuerAssignedId -Expected 'new.admin@example.com' -Message 'Email identity is incorrect.'

$existingResolution = Resolve-BootstrapAdminLocalUser `
    -Email 'admin.user@example.com' `
    -Domain 'shopping1970.onmicrosoft.com' `
    -ExpectedUserObjectId '11111111-1111-1111-1111-111111111111'

Assert-Equal -Actual $existingResolution.User.id -Expected '11111111-1111-1111-1111-111111111111' -Message 'Existing user was not adopted.'
Assert-Equal -Actual $existingResolution.Created -Expected $false -Message 'Existing user was reported as created.'

Assert-Throws `
    -Action {
        Resolve-BootstrapAdminLocalUser `
            -Email 'admin.user@example.com' `
            -Domain 'shopping1970.onmicrosoft.com' `
            -ExpectedUserObjectId '22222222-2222-2222-2222-222222222222'
    } `
    -ExpectedMessage 'does not match configured Bootstrap Admin object ID'

Assert-Throws `
    -Action {
        Resolve-BootstrapAdminLocalUser `
            -Email 'missing@example.com' `
            -Domain 'shopping1970.onmicrosoft.com'
    } `
    -ExpectedMessage 'requires an interactive bootstrap run'

$createRequestsBeforeWhatIf = $script:createRequestCount
$whatIfResolution = Resolve-BootstrapAdminLocalUser `
    -Email 'whatif@example.com' `
    -Domain 'shopping1970.onmicrosoft.com' `
    -AllowCreate `
    -WhatIf

Assert-Equal -Actual $script:createRequestCount -Expected $createRequestsBeforeWhatIf -Message 'WhatIf created a Graph user.'

if ($null -ne $whatIfResolution.TemporaryPassword) {
    throw 'WhatIf generated a temporary password.'
}

$createdResolution = Resolve-BootstrapAdminLocalUser `
    -Email 'created@example.com' `
    -Domain 'shopping1970.onmicrosoft.com' `
    -AllowCreate `
    -Confirm:$false

Assert-Equal -Actual $createdResolution.User.id -Expected '33333333-3333-3333-3333-333333333333' -Message 'Created user was not returned.'
Assert-Equal -Actual $createdResolution.Created -Expected $true -Message 'Created user was not identified as new.'

if ($createdResolution.TemporaryPassword -isnot [Security.SecureString]) {
    throw 'Created user password was not returned as a SecureString.'
}

$createdPassword = ConvertFrom-SecureStringValue -SecureValue $createdResolution.TemporaryPassword
Assert-Equal -Actual $script:capturedCreateBody.passwordProfile.password -Expected $createdPassword -Message 'Generated password did not reach Graph.'
$createdPassword = $null

Write-Host 'External ID bootstrap administrator helper tests passed.'
