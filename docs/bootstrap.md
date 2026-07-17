# Shopping Environment Bootstrap Playbook

This playbook provisions the identity and repository configuration required for a new Shopping installation. It covers GitHub, an Azure subscription, and a Microsoft Entra External ID tenant. Run the read-only verifier successfully before treating an installation as ready.

## Required Information

Collect these non-secret values before starting:

- Canonical GitHub repository (`owner/repository`) and default branch.
- Azure resource tenant ID and subscription ID.
- External ID tenant ID, primary `onmicrosoft.com` domain, and `ciamlogin.com` authority.
- GitHub production reviewer username.
- Optional stable `InstanceName`; otherwise bootstrap derives it from the canonical repository.
- Optional public Web origins for environments using Application Gateway or custom domains.
- Optional External ID user object ID for the initial Admin; interactive selection is also supported.

Create the SQL provisioning password only in memory when the script requests it. Do not place passwords or client-secret values in the configuration file.

## Ownership Model

The bootstrap is authoritative for these dedicated resources:

- `<workload>-<instance>-github-deploy` application, its GitHub federated credentials, and configured Azure RBAC roles.
- `<workload>-<instance>-web` and `<workload>-<instance>-api` applications, their app roles, redirect URIs, delegated permission, API scope, and identifier URI.
- GitHub `dev`, `test`, and `prod` environment protection managed by the scripts.
- The named branch ruleset in `bootstrap.config.psd1`.

Do not manually edit those properties. Update `bootstrap.config.psd1`, preview the change, and rerun the appropriate stage. User flows, external identity providers, and assignments other than the optional bootstrap Admin remain manual.

## Prerequisites

Install:

- Git
- PowerShell 7 or later
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
- App Service worker quota for each selected region and SKU. Each environment requests two workers; quota must cover all environments that will run concurrently.
- Permission to grant tenant-wide consent when `-GrantAdminConsent` is used.
- Permission to assign the initial Admin app roles when `BootstrapAdminUserObjectId` is configured.

Public repositories support the configured CodeQL rules. Private repositories may require GitHub Advanced Security.

## 1. Prepare The Tenants

Create the External ID external tenant manually. Record:

```text
External ID tenant ID
Primary domain, such as contoso.onmicrosoft.com
Authority, such as https://contoso.ciamlogin.com/
```

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

Replace every placeholder. The file is ignored by Git and contains no secrets. `ExternalId.WebRedirectUris` contains local or other fixed callbacks. Bootstrap deterministically generates a resource suffix for each environment and adds the future `azurewebsites.net/signin-oidc` callback before deployment. The same suffix is stored in the matching GitHub environment and supplied to Bicep as `RESOURCE_SUFFIX`, so Entra and Azure use the same hostname on the first deployment. Bicep also retains this suffix in globally named resources such as ACR, Storage, and Key Vault to keep installations and environments distinct.

`InstanceName` identifies one installation. Leave it empty to derive a stable Azure-safe value from the canonical GitHub owner/repository, or set a deliberate value such as `client-a` or `interview-demo`. The resolved value is included in resource groups, tags, app-registration names, generated suffixes, GitHub environment variables, and redirect URLs. Treat one GitHub repository as one installation; use a separate repository and state file for a parallel installation because its `dev`, `test`, and `prod` GitHub environments hold installation-specific values.

Set `ExternalId.PublicWebBaseUrls.<environment>` when users enter through a custom domain, Application Gateway, or another public ingress. Supply the HTTPS origin only, such as `https://shop.example.co.uk`; bootstrap adds `/signin-oidc`. A private production App Service requires this override once its public ingress is defined.

The scripts write generated object IDs to:

```text
scripts/bootstrap-state.local.json
```

This ignored state file contains identifiers and credential expiry metadata only. It never contains passwords or client-secret values.

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
  -ConfigureLocalUserSecrets
```

Use `-RotateWebClientSecret` on the first run or when replacing the GitHub secret. The new secret is returned as a `SecureString` to the orchestrator and is never written to bootstrap state. `-ConfigureLocalUserSecrets` writes the local Web credential and non-secret identity values to the standard per-user .NET user-secrets stores; existing unrelated values are preserved.

When `ExternalId.BootstrapAdminUserObjectId` is set, the script assigns that user to `Admin` on both Web and API enterprise applications. The user must already exist in the External ID tenant.

To select the initial administrator without copying an object ID from the portal, add:

```powershell
-PromptForExternalIdValues
```

Interactive mode prompts for any missing External ID tenant values and lists the tenant users for numbered bootstrap Admin selection. If Microsoft Graph cannot list users, paste the user's object ID at the prompt. The selected non-secret object ID is recorded in `bootstrap-state.local.json` and reused by later bootstrap and verification runs. Omit this switch in automation.

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
  -ConfigureLocalUserSecrets
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
  -AllowInteractiveTenantSwitch
```

Separate stages remain useful for previews and non-secret reruns. Do not rotate a Web credential in a standalone ExternalId process when GitHub also needs the new value; client-secret values cannot be recovered later.

Secrets are piped directly to `gh secret set`. They are not included in command-line arguments or local JSON.

GitHub receives:

- Environment variables for Azure OIDC, the deployment principal object ID, External ID, `WORKLOAD_NAME`, `DEPLOYMENT_INSTANCE`, and the environment-specific `RESOURCE_SUFFIX`.
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
3. Configure email, Microsoft, Google, or other required identity providers.
4. Confirm the bootstrap Admin user can sign in.

When a custom domain or public gateway origin changes, update `ExternalId.PublicWebBaseUrls` and rerun `-Stage ExternalId`. Do not add the callback only in the portal because the script intentionally replaces the complete redirect URI list.

The current production Bicep parameters make the App Services private, while the Application Gateway module is still pending. The generated direct App Service callback is deterministic but is not a public production entry point. Configure and deploy the public ingress, set `ExternalId.PublicWebBaseUrls.prod`, and rerun the External ID stage before testing production sign-in.

Production image deployment also requires a VNet-connected Linux self-hosted GitHub runner labelled `self-hosted`, `linux`, and `shopping-prod`. The runner needs Docker plus private access to ACR, Azure SQL, and App Service. Hosted runners are used for dev and test, with temporary SQL firewall rules removed after migration.

## 10. Verify

```powershell
.\scripts\Test-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1
```

The verifier is read-only. It checks:

- Canonical repository casing, resolved installation name, and non-secret state.
- Federated OIDC subjects and Azure RBAC.
- Web/API roles, redirect URIs, API scope, and admin consent.
- Optional bootstrap Admin assignments.
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
