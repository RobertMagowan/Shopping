# Shopping Environment Bootstrap Playbook

This playbook provisions the identity and repository configuration required for a new Shopping installation. It covers GitHub, an Azure subscription, and a Microsoft Entra External ID tenant. Start with the [end-to-end deployment runbook](end-to-end-deployment-runbook.md) when preparing an empty subscription; use this document as the focused bootstrap reference. Run the read-only verifier successfully before treating an installation as ready.

## Required Information

Collect these non-secret values before starting:

- Canonical GitHub repository (`owner/repository`) and default branch.
- Azure resource tenant ID and subscription ID.
- External ID tenant ID, primary `onmicrosoft.com` domain, and `ciamlogin.com` authority.
- GitHub production reviewer username.
- Optional stable `InstanceName`; otherwise bootstrap derives it from the canonical repository.
- Optional public Web origins for environments using Application Gateway or custom domains.
- Email address for the initial Shopping application administrator.

Create the SQL provisioning password only in memory when the script requests it. Do not place passwords or client-secret values in the configuration file.

## Ownership Model

The bootstrap is authoritative for these dedicated resources:

- `<workload>-<instance>-github-deploy` application, its GitHub federated credentials, and configured Azure RBAC roles.
- `<workload>-<instance>-web` and `<workload>-<instance>-api` applications, their app roles, redirect URIs, delegated permission, API scope, and identifier URI.
- GitHub `dev`, `test`, and `prod` environment protection managed by the scripts.
- The named branch ruleset in `bootstrap.config.psd1`.

Do not manually edit those properties. Update `bootstrap.config.psd1`, preview the change, and rerun the appropriate stage. User flows, external identity providers, and assignments other than the bootstrap Admin remain manual.

## Prerequisites

Install:

- Git
- PowerShell 7 or later (preferred; Windows PowerShell 5.1 is supported)
- Azure CLI
- GitHub CLI
- .NET 10 SDK

Verify the tools:

```powershell
git --version
pwsh --version
az version
gh --version
dotnet --version
```

The operator requires:

- GitHub repository administrator permission.
- Permission to create Entra applications and service principals.
- Permission to assign the configured Azure roles at subscription scope.
- Sufficient Azure Container Apps Consumption quota for the selected regions. Defaults vary by subscription and should be reviewed before deployment.
- Permission to grant tenant-wide consent when `-GrantAdminConsent` is used.
- At least User Administrator permission in the External ID tenant to create the local customer administrator, plus permission to assign application roles.

Public repositories support the configured CodeQL rules. Private repositories may require GitHub Advanced Security.

PowerShell 7 is preferred. If `pwsh` is not installed but Windows PowerShell is available, invoke scripts with `powershell -NoProfile -ExecutionPolicy Bypass -File ...`. Use process-scoped execution-policy changes only; do not weaken machine policy globally.

## 1. Prepare The Tenants

Create the External ID external tenant manually. Record:

```text
External ID tenant ID
Primary domain, such as contoso.onmicrosoft.com
Authority, such as https://contoso.ciamlogin.com/
```

Copy the tenant ID from the **External ID tenant overview** after switching directories. Do not use the home tenant ID shown for the Azure subscription that contains the `ciamDirectories` billing resource. Bootstrap resolves the OpenID Connect metadata before making changes and rejects a tenant ID, primary domain, and authority that do not describe the same External ID tenant.

Also record the tenant ID and subscription ID that will host Azure resources. The Azure resource tenant and External ID tenant may be different.

## 2. Prepare The Repository

The initial repository content, including `.github/workflows`, must exist on the default branch before branch protection is enabled. For a new empty target repository, push the initial imported history first.

Authenticate GitHub CLI:

```powershell
gh auth login
gh repo view <owner>/<repository>
```

The scripts query GitHub's effective OIDC subject prefix before creating case-sensitive credentials. This supports both name-based subjects and the immutable owner/repository ID format used by newer repositories.

## 3. Create Local Configuration

```powershell
Copy-Item .\scripts\bootstrap.config.example.psd1 `
          .\scripts\bootstrap.config.psd1
```

Replace every placeholder. The file is ignored by Git and contains no secrets. `ExternalId.WebRedirectUris` contains local or other fixed callbacks. Bootstrap generates a deterministic resource suffix for globally named resources such as ACR, Storage, and Key Vault, then stores the same value in each GitHub environment for Bicep.

`InstanceName` identifies one installation. Leave it empty to derive a stable Azure-safe value from the canonical GitHub owner/repository, or set a deliberate value such as `client-a` or `interview-demo`. The resolved value is included in resource groups, tags, app-registration names, generated suffixes, and GitHub environment variables. Treat one GitHub repository as one installation; use a separate repository and state file for a parallel installation because its `dev`, `test`, and `prod` GitHub environments hold installation-specific values.

Container Apps assigns its default domain during deployment. For a first deployment without a custom domain, leave `ExternalId.PublicWebBaseUrls.<environment>` empty, deploy infrastructure and application images, copy the Web origin reported by the `app` workflow, set the value, and rerun the External ID stage. When a custom domain is known in advance, supply its HTTPS origin, such as `https://shop.example.co.uk`; bootstrap adds `/signin-oidc`.

The scripts write generated object IDs to:

```text
scripts/bootstrap-state.local.json
```

This ignored state file contains the normalized bootstrap-admin email, identifiers, and credential expiry metadata only. It never contains passwords or client-secret values.

## 4. Preview Each Stage

Sign into the Azure resource tenant:

```powershell
az login --tenant <azure-tenant-id>
az account set --subscription <subscription-id>
```

Preview the deployment identity:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage AzureIdentity `
  -WhatIf
```

Sign into the External ID tenant. `--allow-no-subscriptions` supports an external tenant without an Azure subscription:

```powershell
az login --tenant <external-id-tenant-id> --allow-no-subscriptions
```

Preview the application manifests:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage ExternalId `
  -WhatIf
```

Preview GitHub configuration:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage GitHub `
  -WhatIf
```

For the normal first installation, a single complete preview is preferable because it validates cross-stage inputs:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage All `
  -PromptForExternalIdValues `
  -WhatIf
```

Add `-AllowInteractiveTenantSwitch` when the Azure resource tenant and External ID tenant differ.

## 5. Apply The Azure Identity Stage

Return to the Azure resource tenant and run:

```powershell
az login --tenant <azure-tenant-id>
az account set --subscription <subscription-id>

.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage AzureIdentity
```

This registers the Azure resource providers required by the IaC, creates or adopts one uniquely named deployment application, records its object IDs, creates exact environment-based OIDC credentials, and ensures the configured subscription roles. Provider registration can take several minutes on a new subscription; the script waits for Azure to report completion before continuing.

## 6. Apply The External ID Stage

```powershell
az login --tenant <external-id-tenant-id> --allow-no-subscriptions

.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage ExternalId `
  -RotateWebClientSecret `
  -GrantAdminConsent `
  -ConfigureLocalUserSecrets `
  -PromptForExternalIdValues
```

Use `-RotateWebClientSecret` on the first run or when replacing the GitHub secret. The new secret is returned as a `SecureString` to the orchestrator and is never written to bootstrap state. `-ConfigureLocalUserSecrets` writes the local Web credential and non-secret identity values to the standard per-user .NET user-secrets stores; existing unrelated values are preserved.

Interactive mode prompts for `Bootstrap application administrator email`. Enter the local customer sign-in address. If that exact local `emailAddress` identity does not exist, bootstrap:

- generates a cryptographically random 24-character temporary password;
- creates an enabled local External ID account that must change its password at first sign-in;
- displays the email and temporary password once in the local terminal;
- checkpoints only the normalized email and user object ID;
- assigns `Admin` on both Web and API enterprise applications.

Record the displayed password immediately and provide it through an approved channel. It is not written to configuration, state, user secrets, GitHub, Key Vault, or application logs and cannot be recovered by rerunning bootstrap. Do not run first-account creation under PowerShell transcription, CI, or screen sharing.

If the local account already exists, bootstrap adopts it without resetting its password. A non-interactive run may adopt `ExternalId.BootstrapAdminEmail`, but refuses to create a missing account. `BootstrapAdminUserObjectId` remains a compatibility override; when both values are authoritative they must resolve to the same user.

The Shopping application administrator is a customer account with application roles. It is not the B2B/workforce tenant administrator and receives no Microsoft Entra directory role.

## 7. Configure GitHub

Create the SQL provisioning password in memory:

```powershell
$sqlPassword = Read-Host "SQL provisioning password" -AsSecureString
```

Run the stages together when Azure resources and External ID use the same tenant:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage All `
  -SqlAdministratorPassword $sqlPassword `
  -RotateWebClientSecret `
  -GrantAdminConsent `
  -ConfigureLocalUserSecrets `
  -PromptForExternalIdValues
```

When the tenants differ, keep the generated Web secret in memory by running all stages in one process and allowing the orchestrator to open the External ID sign-in:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage All `
  -SqlAdministratorPassword $sqlPassword `
  -RotateWebClientSecret `
  -GrantAdminConsent `
  -ConfigureLocalUserSecrets `
  -AllowInteractiveTenantSwitch `
  -PromptForExternalIdValues
```

Separate stages remain useful for previews and non-secret reruns. Do not rotate a Web credential in a standalone ExternalId process when GitHub also needs the new value; client-secret values cannot be recovered later.

Secrets are piped directly to `gh secret set`. They are not included in command-line arguments or local JSON.

GitHub receives:

- Environment variables for Azure OIDC, the deployment principal object ID, External ID, `WORKLOAD_NAME`, `DEPLOYMENT_INSTANCE`, and the environment-specific `RESOURCE_SUFFIX`.
- Environment capability variables for `MANAGED_REDIS_LOCATION` and `SQL_ZONE_REDUNDANT`, derived from `Azure.ManagedRedisLocations` and `Azure.SqlZoneRedundancy` in the bootstrap configuration.
- Environment secrets for SQL provisioning and the Web client credential.
- No deployment approval for dev or test.
- Required reviewer approval for production.
- Production deployment restricted to the exact configured default branch.

## 8. Enable Branch Protection Last

Only after `ci.yml`, `infra.yml`, and `codeql.yml` exist on the default branch, run:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage GitHub `
  -ConfigureRuleset
```

The script manages only the exactly named ruleset from configuration. It requires build, test, container-build, and all environment-specific IaC validation checks. If another ruleset already protects the branch, it stops and requires explicit adoption by name.

## 9. Complete Manual External ID Steps

In the Entra admin center:

1. Create or select the customer sign-up and sign-in user flow.
2. Add the `<workload>-<instance>-web` application to the user flow.
3. Configure email, Google, or other customer identity providers. Personal Microsoft accounts require a deliberately configured customer federation; the workforce/B2B Microsoft provider is not the same feature.
4. Run the interactive External ID bootstrap command in section 6 to create or adopt the local customer administrator.
5. Sign in with the displayed temporary password and complete the mandatory password change.

Self-service sign-up creates a customer account but does not automatically assign the current `Customer` app role. Until an application provisioning flow or baseline-customer authorization change is implemented, newly registered customers require a manual `Customer` role assignment before using role-protected cart endpoints.

After the first application deployment, copy each reported Container Apps Web origin into `ExternalId.PublicWebBaseUrls`, then rerun `-Stage ExternalId`. Repeat this when a custom domain or public gateway origin changes. Do not add callbacks only in the portal because the script intentionally replaces the complete redirect URI list.

Application deployments use GitHub-hosted Linux runners. For production, the workflow temporarily allowlists only the current runner IP on ACR and Azure SQL, then restores private-only access in `always()` cleanup steps before deploying the runtime revision. No persistent self-hosted runner is required.

## 10. Verify

```powershell
.\scripts\Test-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1
```

The verifier is read-only. It checks:

- Canonical repository casing, resolved installation name, and non-secret state.
- Federated OIDC subjects and Azure RBAC.
- Web/API roles, redirect URIs, API scope, and admin consent.
- Bootstrap Admin enabled status, local email identity, object ID, and both application-role assignments.
- GitHub environment variables, deterministic resource suffixes, and secret presence.
- Production reviewer and branch restrictions.
- The managed branch ruleset and exact required status checks.

User-flow and identity-provider verification remains a manual result because the bootstrap identity is not granted user-flow administration permissions.

## 11. Hand Off To Deployment

After automated verification and the manual user-flow check pass, follow the [Shopping CI/CD Deployment Playbook](deployment-playbook.md). Merging IaC changes to `master` automatically reconciles development infrastructure and then deploys the development application.

For an existing installation, run the updated GitHub bootstrap stage and verifier before merging workflow changes that introduce new environment variables, secrets, or required checks. This prevents the automatic development deployment from using stale repository configuration.

## Legacy Secret File

`scripts/github-bootstrap.local.json` is no longer used. After confirming that GitHub contains both required environment secrets, remove the local file manually:

```powershell
Remove-Item .\scripts\github-bootstrap.local.json
```

Never commit or archive that legacy file.
