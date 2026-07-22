$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -ChildPath "bootstrap-github.ps1"
$script = Get-Content -LiteralPath $scriptPath -Raw

if ($script -match 'Invoke-Gh\s+-Arguments\s+@\("auth",\s*"status"\)') {
    throw "GitHub bootstrap must not rely on the rate-sensitive gh auth status endpoint."
}

if ($script -notmatch '\$canonicalRepository\s*=\s*Get-CanonicalGitHubRepository\s+-Repository\s+\$Repository') {
    throw "GitHub bootstrap must resolve and verify access to the target repository."
}

Write-Host "GitHub bootstrap preflight tests passed."
