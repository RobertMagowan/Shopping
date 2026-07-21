Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-BootstrapAdminGraphJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [object]$Body
    )

    $token = & az account get-access-token `
        --resource-type ms-graph `
        --query accessToken `
        --output tsv `
        --only-show-errors

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to acquire a Microsoft Graph token. Sign in to the External ID tenant first."
    }

    $json = $null

    try {
        $parameters = @{
            Method = $Method
            Uri = $Uri
            Headers = @{ Authorization = "Bearer $token" }
        }

        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 20
            $parameters.ContentType = "application/json"
            $parameters.Body = $json
        }

        return Invoke-RestMethod @parameters
    }
    finally {
        $json = $null
        $token = $null
    }
}

function Normalize-BootstrapAdminEmail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    $normalizedEmail = $Email.Trim().ToLowerInvariant()

    try {
        $address = [System.Net.Mail.MailAddress]::new($normalizedEmail)
    }
    catch {
        throw "Bootstrap Admin email '$Email' is not a valid email address."
    }

    if (-not [string]::Equals($address.Address, $normalizedEmail, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Bootstrap Admin email '$Email' is not a valid email address."
    }

    return $normalizedEmail
}

function Get-CryptographicRandomIndex {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.RandomNumberGenerator]$RandomNumberGenerator,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$UpperBound
    )

    $buffer = New-Object byte[] 4
    $upperBoundValue = [uint32]$UpperBound
    $exclusiveLimit = [uint64]::MaxValue
    $exclusiveLimit = ([uint64][uint32]::MaxValue + 1) - (([uint64][uint32]::MaxValue + 1) % $upperBoundValue)

    do {
        $RandomNumberGenerator.GetBytes($buffer)
        $value = [uint64][BitConverter]::ToUInt32($buffer, 0)
    } while ($value -ge $exclusiveLimit)

    return [int]($value % $upperBoundValue)
}

function New-BootstrapAdminTemporaryPassword {
    param(
        [ValidateRange(16, 128)]
        [int]$Length = 24
    )

    $characterSets = @(
        "ABCDEFGHJKLMNPQRSTUVWXYZ",
        "abcdefghijkmnopqrstuvwxyz",
        "23456789",
        '!@#$%*+-_='
    )
    $allCharacters = $characterSets -join ""
    $characters = New-Object 'System.Collections.Generic.List[char]'
    $randomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        foreach ($characterSet in $characterSets) {
            $index = Get-CryptographicRandomIndex `
                -RandomNumberGenerator $randomNumberGenerator `
                -UpperBound $characterSet.Length
            $characters.Add($characterSet[$index])
        }

        while ($characters.Count -lt $Length) {
            $index = Get-CryptographicRandomIndex `
                -RandomNumberGenerator $randomNumberGenerator `
                -UpperBound $allCharacters.Length
            $characters.Add($allCharacters[$index])
        }

        for ($index = $characters.Count - 1; $index -gt 0; $index--) {
            $swapIndex = Get-CryptographicRandomIndex `
                -RandomNumberGenerator $randomNumberGenerator `
                -UpperBound ($index + 1)
            $current = $characters[$index]
            $characters[$index] = $characters[$swapIndex]
            $characters[$swapIndex] = $current
        }
    }
    finally {
        $randomNumberGenerator.Dispose()
    }

    return -join $characters
}

function Test-BootstrapAdminLocalIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,

        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $normalizedEmail = Normalize-BootstrapAdminEmail -Email $Email
    $normalizedDomain = $Domain.Trim()
    $identities = @(Get-ObjectPropertyValue -InputObject $User -Name "identities")
    $matches = @($identities | Where-Object {
        [string]::Equals([string]$_.signInType, "emailAddress", [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$_.issuer, $normalizedDomain, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$_.issuerAssignedId, $normalizedEmail, [StringComparison]::OrdinalIgnoreCase)
    })

    return $matches.Count -gt 0
}

function Get-BootstrapAdminVerificationResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,

        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [bool]$WebAdminAssigned,

        [Parameter(Mandatory = $true)]
        [bool]$ApiAdminAssigned
    )

    $userObjectId = [string](Get-ObjectPropertyValue -InputObject $User -Name "id")

    if ($User.accountEnabled -ne $true) {
        return [pscustomobject]@{
            Status = "Fail"
            Detail = "Bootstrap Admin '$userObjectId' is disabled."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Email) -and
        -not (Test-BootstrapAdminLocalIdentity -User $User -Email $Email -Domain $Domain)) {
        return [pscustomobject]@{
            Status = "Fail"
            Detail = "Bootstrap Admin '$userObjectId' does not have the expected local email identity '$Email'."
        }
    }

    if (-not $WebAdminAssigned -or -not $ApiAdminAssigned) {
        return [pscustomobject]@{
            Status = "Fail"
            Detail = "Bootstrap Admin '$userObjectId' is missing one or both application Admin assignments."
        }
    }

    $identityDetail = if ([string]::IsNullOrWhiteSpace($Email)) {
        "legacy object-ID configuration"
    }
    else {
        Normalize-BootstrapAdminEmail -Email $Email
    }

    return [pscustomobject]@{
        Status = "Pass"
        Detail = "Enabled administrator '$identityDetail' is assigned to both Web and API Admin roles."
    }
}

function Get-BootstrapAdminLocalUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $normalizedEmail = Normalize-BootstrapAdminEmail -Email $Email
    $normalizedDomain = $Domain.Trim()
    $users = @()
    $uri = "https://graph.microsoft.com/v1.0/users?`$select=id,accountEnabled,displayName,mail,identities"

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $response = Invoke-BootstrapAdminGraphJson -Method "GET" -Uri $uri -Body $null
        $users += @($response.value)
        $uri = [string](Get-ObjectPropertyValue -InputObject $response -Name "@odata.nextLink")
    }

    $matches = @($users | Where-Object {
        Test-BootstrapAdminLocalIdentity -User $_ -Email $normalizedEmail -Domain $normalizedDomain
    })

    if ($matches.Count -gt 1) {
        throw "More than one local External ID user matches '$normalizedEmail' in '$normalizedDomain'. Resolve the duplicate identities before rerunning bootstrap."
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function New-BootstrapAdminLocalUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$TemporaryPassword
    )

    $normalizedEmail = Normalize-BootstrapAdminEmail -Email $Email
    $normalizedDomain = $Domain.Trim()
    $body = @{
        accountEnabled = $true
        creationType = "LocalAccount"
        displayName = "Shopping Bootstrap Administrator"
        identities = @(
            @{
                signInType = "emailAddress"
                issuer = $normalizedDomain
                issuerAssignedId = $normalizedEmail
            }
        )
        mail = $normalizedEmail
        passwordProfile = @{
            password = $TemporaryPassword
            forceChangePasswordNextSignIn = $true
        }
        passwordPolicies = "DisablePasswordExpiration"
    }

    $user = Invoke-BootstrapAdminGraphJson `
        -Method "POST" `
        -Uri "https://graph.microsoft.com/v1.0/users" `
        -Body $body

    if ($null -eq $user -or [string]::IsNullOrWhiteSpace([string]$user.id)) {
        throw "Microsoft Graph did not return the created Bootstrap Admin user."
    }

    return $user
}

function Resolve-BootstrapAdminLocalUser {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [string]$ExpectedUserObjectId,

        [switch]$AllowCreate
    )

    $normalizedEmail = Normalize-BootstrapAdminEmail -Email $Email
    $user = Get-BootstrapAdminLocalUser `
        -Email $normalizedEmail `
        -Domain $Domain

    if ($null -ne $user) {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedUserObjectId) -and
            -not [string]::Equals([string]$user.id, $ExpectedUserObjectId, [StringComparison]::OrdinalIgnoreCase)) {
            throw "External ID user '$($user.id)' for '$normalizedEmail' does not match configured Bootstrap Admin object ID '$ExpectedUserObjectId'."
        }

        return [pscustomobject]@{
            Email = $normalizedEmail
            User = $user
            Created = $false
            TemporaryPassword = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedUserObjectId)) {
        throw "No local External ID user for '$normalizedEmail' matches configured Bootstrap Admin object ID '$ExpectedUserObjectId'."
    }

    if (-not $AllowCreate) {
        throw "Creating Bootstrap Admin '$normalizedEmail' requires an interactive bootstrap run. Rerun Initialize-ShoppingBootstrap.ps1 with -Stage ExternalId -PromptForExternalIdValues."
    }

    if (-not $PSCmdlet.ShouldProcess($normalizedEmail, "Create local External ID Bootstrap Admin with a generated temporary password")) {
        return [pscustomobject]@{
            Email = $normalizedEmail
            User = $null
            Created = $false
            TemporaryPassword = $null
        }
    }

    $temporaryPassword = New-BootstrapAdminTemporaryPassword

    $user = New-BootstrapAdminLocalUser `
        -Email $normalizedEmail `
        -Domain $Domain `
        -TemporaryPassword $temporaryPassword

    $secureTemporaryPassword = ConvertTo-SecureString `
        -String $temporaryPassword `
        -AsPlainText `
        -Force
    $temporaryPassword = $null

    return [pscustomobject]@{
        Email = $normalizedEmail
        User = $user
        Created = $true
        TemporaryPassword = $secureTemporaryPassword
    }
}
