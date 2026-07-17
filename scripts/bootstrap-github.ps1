[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [string]$Branch = "master",

    [Parameter(Mandatory = $true)]
    [string]$InstanceName,

    [string[]]$Environments = @("dev", "test", "prod"),

    [string[]]$ProdReviewerUsers,

    [hashtable]$EnvironmentVariables = @{},

    [hashtable]$EnvironmentVariablesByEnvironment = @{},

    [hashtable]$EnvironmentSecrets = @{},

    [string]$StatePath = ".\scripts\bootstrap-state.local.json",

    [string]$RulesetName,

    [switch]$ConfigureRuleset,

    [switch]$PassThru
)

. "$PSScriptRoot\bootstrap-shared.ps1"

function Invoke-Gh {
    param([string[]]$Arguments)

    & gh @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "gh command failed: gh $($Arguments -join ' ')"
    }
}

function Invoke-GhApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body
    )

    $tempFile = New-TemporaryFile

    try {
        if ($null -eq $Body) {
            & gh api --method $Method $Path | Out-Null
        }
        else {
            $json = $Body | ConvertTo-Json -Depth 50
            $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($tempFile.FullName, $json, $utf8WithoutBom)
            & gh api --method $Method $Path --input $tempFile.FullName | Out-Null
        }

        if ($LASTEXITCODE -ne 0) {
            throw "gh api failed: $Method $Path"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Get-GhApiJson {
    param([string]$Path)

    $json = & gh api $Path

    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json
}

function Set-EnvironmentValues {
    param([string]$EnvironmentName)

    $variables = @{}

    foreach ($name in $EnvironmentVariables.Keys) {
        $variables[$name] = $EnvironmentVariables[$name]
    }

    $environmentOverrides = $EnvironmentVariablesByEnvironment[$EnvironmentName]

    if ($null -ne $environmentOverrides) {
        foreach ($name in $environmentOverrides.Keys) {
            $variables[$name] = $environmentOverrides[$name]
        }
    }

    foreach ($name in $variables.Keys) {
        $value = [string]$variables[$name]

        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Environment variable '$name' is empty. Refusing to create a partially configured '$EnvironmentName' environment."
        }

        if ($PSCmdlet.ShouldProcess("$EnvironmentName/$name", "Set GitHub environment variable")) {
            Invoke-Gh -Arguments @("variable", "set", $name, "--repo", $canonicalRepository, "--env", $EnvironmentName, "--body", $value)
        }
    }

    foreach ($name in $EnvironmentSecrets.Keys) {
        $secureValue = $EnvironmentSecrets[$name]

        if ($secureValue -isnot [Security.SecureString]) {
            throw "Environment secret '$name' must be supplied as a SecureString."
        }

        if ($PSCmdlet.ShouldProcess("$EnvironmentName/$name", "Set GitHub environment secret")) {
            $plainValue = ConvertFrom-SecureStringValue -SecureValue $secureValue

            try {
                $plainValue | & gh secret set $name --repo $canonicalRepository --env $EnvironmentName

                if ($LASTEXITCODE -ne 0) {
                    throw "gh secret set failed for '$EnvironmentName/$name'."
                }
            }
            finally {
                $plainValue = $null
            }
        }
    }
}

function Get-UserReviewer {
    param([string]$UserName)

    $user = Get-GhApiJson -Path "users/$UserName"

    return @{
        type = "User"
        id = [int]$user.id
    }
}

function Set-Environment {
    param(
        [string]$EnvironmentName,
        [object[]]$Reviewers = @()
    )

    $deploymentBranchPolicy = if ($EnvironmentName -eq "prod") {
        @{
            protected_branches = $false
            custom_branch_policies = $true
        }
    }
    else {
        $null
    }

    $body = @{
        wait_timer = 0
        prevent_self_review = $false
        reviewers = $Reviewers
        deployment_branch_policy = $deploymentBranchPolicy
    }

    if ($PSCmdlet.ShouldProcess($EnvironmentName, "Create or replace Shopping-managed GitHub environment protection")) {
        Invoke-GhApiJson -Method "PUT" -Path "repos/$canonicalRepository/environments/$EnvironmentName" -Body $body
    }
}

function Set-ProductionBranchPolicy {
    if (-not $PSCmdlet.ShouldProcess("prod/$Branch", "Reconcile exact production deployment branch policy")) {
        return
    }

    $path = "repos/$canonicalRepository/environments/prod/deployment-branch-policies"
    $policyResponse = Get-GhApiJson -Path $path
    $policies = @($policyResponse.branch_policies)
    $matchingPolicies = @($policies | Where-Object { $_.name -ceq $Branch -and $_.type -eq "branch" })

    if ($matchingPolicies.Count -eq 0) {
        Invoke-GhApiJson -Method "POST" -Path $path -Body @{
            name = $Branch
            type = "branch"
        }
    }

    foreach ($policy in $policies | Where-Object { $_.name -cne $Branch -or $_.type -ne "branch" }) {
        Invoke-GhApiJson -Method "DELETE" -Path "$path/$($policy.id)" -Body $null
    }
}

function Assert-RequiredWorkflowsExist {
    $requiredWorkflowFiles = @(
        ".github/workflows/ci.yml",
        ".github/workflows/infra.yml",
        ".github/workflows/codeql.yml"
    )

    foreach ($workflowFile in $requiredWorkflowFiles) {
        & gh api "repos/$canonicalRepository/contents/$workflowFile`?ref=$Branch" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Required workflow '$workflowFile' does not exist on '$Branch'. Push the workflows before enabling required checks."
        }
    }
}

function Set-BranchRuleset {
    param([string]$ManagedRulesetName)

    Assert-RequiredWorkflowsExist
    $repositoryDetails = Get-GhApiJson -Path "repos/$canonicalRepository"

    if ($repositoryDetails.visibility -eq "private") {
        $securityAndAnalysis = Get-ObjectPropertyValue -InputObject $repositoryDetails -Name "security_and_analysis"
        $advancedSecurity = Get-ObjectPropertyValue -InputObject $securityAndAnalysis -Name "advanced_security"
        $advancedSecurityStatus = Get-ObjectPropertyValue -InputObject $advancedSecurity -Name "status"

        if ($advancedSecurityStatus -ne "enabled") {
            throw "The configured CodeQL and code-quality rules require GitHub Advanced Security for this private repository. Enable it or deliberately revise the managed ruleset."
        }
    }

    $rules = @(
        @{ type = "deletion" },
        @{ type = "non_fast_forward" },
        @{
            type = "code_quality"
            parameters = @{ severity = "errors" }
        },
        @{
            type = "required_status_checks"
            parameters = @{
                do_not_enforce_on_create = $false
                strict_required_status_checks_policy = $true
                required_status_checks = @(
                    @{ context = "ci-build" },
                    @{ context = "ci-test" },
                    @{ context = "infra-static-validation-dev" },
                    @{ context = "infra-static-validation-test" },
                    @{ context = "infra-static-validation-prod" }
                )
            }
        },
        @{
            type = "code_scanning"
            parameters = @{
                code_scanning_tools = @(
                    @{
                        tool = "CodeQL"
                        security_alerts_threshold = "high_or_higher"
                        alerts_threshold = "errors_and_warnings"
                    }
                )
            }
        },
        @{
            type = "pull_request"
            parameters = @{
                allowed_merge_methods = @("merge", "squash", "rebase")
                dismiss_stale_reviews_on_push = $true
                required_reviewers = @()
                require_code_owner_review = $false
                require_last_push_approval = $false
                required_approving_review_count = 0
                required_review_thread_resolution = $true
            }
        }
    )

    $rulesets = @(Get-GhApiJson -Path "repos/$canonicalRepository/rulesets?includes_parents=false")
    $existing = @($rulesets | Where-Object { $_.name -eq $ManagedRulesetName })

    if ($existing.Count -gt 1) {
        throw "More than one ruleset named '$ManagedRulesetName' exists."
    }

    if ($existing.Count -eq 0) {
        foreach ($candidate in $rulesets) {
            $details = Get-GhApiJson -Path "repos/$canonicalRepository/rulesets/$($candidate.id)"
            $includedRefs = @($details.conditions.ref_name.include)

            if ($details.target -eq "branch" -and $includedRefs -contains "refs/heads/$Branch") {
                throw "Ruleset '$($candidate.name)' already protects '$Branch'. Pass -RulesetName '$($candidate.name)' to adopt it explicitly."
            }
        }
    }

    $body = @{
        name = $ManagedRulesetName
        target = "branch"
        enforcement = "active"
        bypass_actors = @()
        conditions = @{
            ref_name = @{
                include = @("refs/heads/$Branch")
                exclude = @()
            }
        }
        rules = $rules
    }

    if ($existing.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($ManagedRulesetName, "Create Shopping-managed branch ruleset")) {
            Invoke-GhApiJson -Method "POST" -Path "repos/$canonicalRepository/rulesets" -Body $body
        }

        return $null
    }

    if ($PSCmdlet.ShouldProcess($ManagedRulesetName, "Replace Shopping-managed branch ruleset")) {
        Invoke-GhApiJson -Method "PUT" -Path "repos/$canonicalRepository/rulesets/$($existing[0].id)" -Body $body
    }

    return $existing[0].id
}

Assert-Command -Name "gh"
Invoke-Gh -Arguments @("auth", "status")
$canonicalRepository = Get-CanonicalGitHubRepository -Repository $Repository
$managedRulesetName = if ([string]::IsNullOrWhiteSpace($RulesetName)) { "protected $Branch" } else { $RulesetName }

$state = Read-BootstrapState -Path $StatePath
$rootState = Get-OrAddStateSection -State $state -Name "bootstrap"
Assert-StateValue -StateSection $rootState -Name "repository" -ExpectedValue $canonicalRepository
Assert-StateValue -StateSection $rootState -Name "instanceName" -ExpectedValue $InstanceName
$githubState = Get-OrAddStateSection -State $state -Name "github"
Assert-StateValue -StateSection $githubState -Name "branch" -ExpectedValue $Branch
Assert-StateValue -StateSection $githubState -Name "rulesetName" -ExpectedValue $managedRulesetName

foreach ($environmentName in $Environments) {
    $reviewers = @()

    if ($environmentName -eq "prod") {
        if ($null -eq $ProdReviewerUsers -or $ProdReviewerUsers.Count -eq 0) {
            throw "Pass at least one -ProdReviewerUsers value so production requires approval."
        }

        $reviewers = @($ProdReviewerUsers | ForEach-Object { Get-UserReviewer -UserName $_ })
    }

    Set-Environment -EnvironmentName $environmentName -Reviewers $reviewers

    if ($environmentName -eq "prod") {
        Set-ProductionBranchPolicy
    }

    Set-EnvironmentValues -EnvironmentName $environmentName
}

$rulesetId = Get-ObjectPropertyValue -InputObject $githubState -Name "rulesetId"

if ($ConfigureRuleset) {
    $rulesetId = Set-BranchRuleset -ManagedRulesetName $managedRulesetName
}
else {
    Write-Host "Branch ruleset was not changed. Pass -ConfigureRuleset only after required workflow files exist on '$Branch'."
}

if ($null -ne $rulesetId) {
    Set-ObjectPropertyValue -InputObject $githubState -Name "rulesetId" -Value $rulesetId
}

if ($PSCmdlet.ShouldProcess($StatePath, "Write non-secret bootstrap state")) {
    Save-BootstrapState -State $state -Path $StatePath
}

Write-Host "GitHub bootstrap completed for $canonicalRepository."
Write-Host "Production approval is configured for: $($ProdReviewerUsers -join ', ')."
Write-Host "Production deployment is restricted to '$Branch'."

if ($PassThru) {
    [pscustomobject]@{
        Repository = $canonicalRepository
        Branch = $Branch
        RulesetName = $managedRulesetName
        RulesetId = $rulesetId
    }
}
