Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        $response = Invoke-AzRestJson -Method "GET" -Uri $uri -Body $null
        $users += @($response.value)
        $uri = [string](Get-ObjectPropertyValue -InputObject $response -Name "@odata.nextLink")
    }

    $matches = @($users | Where-Object {
        $user = $_
        @($user.identities | Where-Object {
            [string]::Equals([string]$_.signInType, "emailAddress", [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.issuer, $normalizedDomain, [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.issuerAssignedId, $normalizedEmail, [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
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

    $user = Invoke-AzRestJson `
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

    try {
        $user = New-BootstrapAdminLocalUser `
            -Email $normalizedEmail `
            -Domain $Domain `
            -TemporaryPassword $temporaryPassword
    }
    catch {
        $user = Get-BootstrapAdminLocalUser `
            -Email $normalizedEmail `
            -Domain $Domain

        if ($null -ne $user) {
            return [pscustomobject]@{
                Email = $normalizedEmail
                User = $user
                Created = $false
                TemporaryPassword = $null
            }
        }

        throw
    }

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
