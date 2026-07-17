# Shopping Infrastructure

This folder contains Azure infrastructure definitions for the Shopping application.

For the complete setup, including Azure app registrations, GitHub OIDC, GitHub Environments, branch protection, and required tools, see the [Shopping Environment Bootstrap Playbook](../docs/bootstrap.md).

## Deployment Model

`main.bicep` is a subscription-scope deployment. It creates the environment resource group, then deploys the environment resources from `modules/environment.bicep`.

The template is tenant-neutral. A third party can deploy it into their own tenant and subscription by supplying their own GitHub OIDC identity values. Bootstrap derives `deploymentInstance` from the canonical GitHub owner/repository by default; set `InstanceName` explicitly when a different stable installation label is required.

The current baseline deploys:

- VNet and subnets for App Gateway, APIM, App Service integration, and private endpoints.
- `Shopping.Web` and `Shopping.Api` App Services with system-assigned managed identities.
- App Service Plan.
- Azure SQL server and database.
- Storage account and `product-images` blob container.
- Key Vault with RBAC and purge protection.
- Azure Cache for Redis.
- Log Analytics and workspace-based Application Insights.
- Optional private endpoints and private DNS for App Service, SQL, Blob Storage, Key Vault, and Redis.
- Optional Azure Front Door Premium image endpoint with a private Blob Storage origin.

APIM, Application Gateway WAF, custom domains, and certificates are intentionally left for follow-up modules because they require tenant/domain-specific choices.

## Bootstrap

Use the [Shopping Environment Bootstrap Playbook](../docs/bootstrap.md) to configure the Azure deployment identity, External ID applications, GitHub environments, secrets, production approval, and branch ruleset.

The bootstrap resolves canonical GitHub repository casing before creating OIDC subjects, keeps generated IDs in an ignored non-secret state file, and pipes secret values directly to GitHub. It supports separate Azure resource and External ID tenants.

Bootstrap also generates an environment-specific `RESOURCE_SUFFIX` before deployment. Bicep consumes that exact value, allowing the External ID callback for the future Web App hostname to be registered before the App Service exists. Configure `ExternalId.PublicWebBaseUrls` when an environment uses Application Gateway or a custom public domain instead of the direct App Service origin.

The final bootstrap step must be read-only verification:

```powershell
.\scripts\Test-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1
```

`AZURE_CLIENT_ID` refers to the GitHub deployment application, not the Shopping.Web or Shopping.Api runtime applications. The current subscription-scoped deployment roles are intentionally explicit in bootstrap configuration and should be reviewed for each target subscription.

## Environment Parameter Files

The workflow uses:

```text
infra/parameters/dev.bicepparam
infra/parameters/test.bicepparam
infra/parameters/prod.bicepparam
```

`dev` and `test` default to lower-cost settings and public App Service ingress:

```text
enablePrivateEndpoints: false
allowPublicAppAccess: true
```

Azure-hosted `dev` is not the same as local `Development`. Deployed App Services are configured with:

```text
ASPNETCORE_ENVIRONMENT=Dev
```

That prevents Azure-hosted development from loading local-only `appsettings.Development.json` values. Runtime settings for deployed `dev`, `test`, and `prod` come from App Service configuration. Sensitive values, such as the Web client secret and Redis connection string, are stored in Key Vault and exposed through App Service Key Vault references.

`prod` defaults to private endpoints and disabled public App Service ingress:

```text
enablePrivateEndpoints: true
allowPublicAppAccess: false
enableFrontDoorImageDelivery: true
```

Production app package deployment to private-only App Services will require a private deployment path, such as a self-hosted GitHub runner with VNet access, or an explicit temporary/public deployment strategy. Do not disable private ingress merely to make deployment convenient without documenting the risk.

Production image delivery uses Azure Front Door Premium:

```text
Browser -> Front Door Premium -> Private Link -> Blob Storage product-images container
```

The API is configured to return image URLs using the Front Door endpoint and shared short-lived SAS query strings. The default SAS lifetime is 10 minutes. Front Door caches by full query string so all app users share cache entries during the same SAS window.

The Front Door private endpoint connection to the Storage account may require approval in the target subscription after the first deployment.

## Pipeline Behaviour

The `infra` workflow:

- builds all Bicep parameter files on pull requests and pushes to `master`,
- deploys a selected environment only from manual workflow dispatch,
- validates and runs `what-if` before every deployment,
- tears down a selected environment only from manual workflow dispatch,
- requires a typed teardown confirmation such as `destroy-dev`,
- deletes the environment resource group during teardown.

Use `what-if` output as the reviewable deployment plan before approving production changes.

To deploy:

```text
Actions -> infra -> Run workflow
operation: deploy
environmentName: dev, test, or prod
```

To tear down:

```text
Actions -> infra -> Run workflow
operation: destroy
environmentName: dev, test, or prod
confirmDestroy: destroy-dev, destroy-test, or destroy-prod
```

If an environment uses a custom resource group name, set `RESOURCE_GROUP_NAME` as a GitHub environment variable for that environment. Otherwise the workflow deletes the default resource group name:

```text
rg-{workloadName}-{deploymentInstance}-{environmentName}-{location}
```
