# Shopping Infrastructure

This folder contains Azure infrastructure definitions for the Shopping application.

For a complete installation and delivery lifecycle, start with the [Shopping End-to-End Deployment Runbook](../docs/end-to-end-deployment-runbook.md). For focused details, see the [Shopping Environment Bootstrap Playbook](../docs/bootstrap.md) and [Shopping CI/CD Deployment Playbook](../docs/deployment-playbook.md).

## Deployment Model

`main.bicep` is a subscription-scope deployment. It creates the environment resource group, then deploys the environment resources from `modules/environment.bicep`.

`modules/environment.bicep` is a resource-group orchestrator with no direct resource declarations. Capability modules are deliberately cohesive rather than one file per Azure resource:

| Module | Responsibility |
| --- | --- |
| `network.bicep` | NSG, VNet, reserved subnets, and optional NAT egress |
| `container-platform.bicep` | Log Analytics, Application Insights, and Container Apps environment |
| `identities.bicep` | Web/API user-assigned managed identities |
| `container-registry.bicep` | ACR and environment-specific network/SKU settings |
| `key-vault.bicep` | Key Vault and optional Web client-secret storage |
| `storage.bicep` | Private Blob Storage and `product-images` container |
| `sql.bicep` | Azure SQL server, database, and Entra administrator |
| `redis.bicep` | Azure Managed Redis, database, and Key Vault connection-string secret |
| `image-delivery.bicep` | Optional Front Door Premium private Blob origin |
| `access-control.bicep` | ACR, Blob, and Key Vault role assignments |
| `private-endpoints.bicep` | Private DNS, VNet links, endpoints, and zone groups |
| `container-apps.bicep` | Internal API and public Web application definitions |

Run `infra/tests/Test-BicepModules.ps1` to enforce this composition. Module outputs create normal dependencies; explicit dependencies are retained where a module uses deterministic names rather than outputs, or Container Apps must wait for RBAC assignments.

The template is tenant-neutral. A third party can deploy it into their own tenant and subscription by supplying their own GitHub OIDC identity values. Bootstrap derives `deploymentInstance` from the canonical GitHub owner/repository by default; set `InstanceName` explicitly when a different stable installation label is required.

The current baseline deploys:

- An Azure Container Apps Consumption environment with external HTTPS ingress for `Shopping.Web` and internal-only ingress for `Shopping.Api`.
- One warm replica per app in dev/test; production starts with two and can scale to ten.
- User-assigned managed identities for runtime access, Key Vault references, and ACR image pulls.
- Azure Container Registry with administrative credentials disabled.
- Azure SQL server and database.
- Storage account and `product-images` blob container.
- Key Vault with RBAC and purge protection.
- Azure Managed Redis using the `Balanced_B0` SKU, with high availability enabled in production.
- Log Analytics and workspace-based Application Insights.
- A VNet with a delegated Container Apps infrastructure subnet, reserved ingress/APIM subnets, and a private-endpoint subnet.
- Optional private endpoints and Private DNS for SQL, Blob Storage, Key Vault, Redis, and Container Registry.
- Production NAT Gateway egress with a stable public IP when private endpoints are enabled.
- Optional Azure Front Door Premium image endpoint with a private Blob Storage origin.

APIM, Application Gateway WAF, custom domains, and certificates remain follow-up modules because they require tenant/domain-specific choices. Container Apps managed TLS is the baseline public ingress.

## Bootstrap

Use the [Shopping Environment Bootstrap Playbook](../docs/bootstrap.md) to configure the Azure deployment identity, External ID applications, GitHub environments, secrets, production approval, and branch ruleset.

The bootstrap resolves canonical GitHub repository casing before creating OIDC subjects, keeps generated IDs in an ignored non-secret state file, and pipes secret values directly to GitHub. It supports separate Azure resource and External ID tenants.

Bootstrap generates an environment-specific `RESOURCE_SUFFIX` before deployment and Bicep consumes that exact value for stable resource names. Container Apps assigns its default FQDN during deployment. After the first `app` workflow, copy the reported Web origin to `ExternalId.PublicWebBaseUrls.<environment>` and rerun the External ID bootstrap stage before testing sign-in. A known custom domain can be configured before deployment.

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

`dev` and `test` use the lower-cost Container Apps baseline:

```text
enablePrivateEndpoints: false
containerAppMinReplicas: 1
containerAppMaxReplicas: 1
```

Azure-hosted `dev` is not the same as local `Development`. Deployed Container Apps are configured with:

```text
ASPNETCORE_ENVIRONMENT=Dev
```

That prevents Azure-hosted development from loading local-only `appsettings.Development.json` values. Runtime settings for deployed `dev`, `test`, and `prod` come from Container Apps environment variables. Sensitive values, such as the Web client secret and Redis connection string, stay in Key Vault and are exposed through Container Apps Key Vault secret references.

The initial infrastructure deployment creates ACR, user-assigned identities, RBAC, networking, SQL, Redis, Storage, and Key Vault without creating the application containers. The `app` workflow pushes both immutable commit-SHA images, migrates SQL, and then creates or updates the Container Apps.

Azure Managed Redis uses encrypted client traffic on port `10000`. Dev and test permit public network access for the managed Container Apps environment; production disables public access and resolves the cache through `privatelink.redis.azure.net`.

`MANAGED_REDIS_LOCATION` can place the managed cache in another UK region when the application region has insufficient cache capacity; the production private endpoint remains in the application VNet. `SQL_ZONE_REDUNDANT` must match the selected subscription, region, and SQL SKU capability. Keep it enabled for production where supported; disabling it retains Azure SQL's built-in local availability but removes availability-zone outage protection.

Dev and test also expose Azure SQL through its public endpoint. The SQL module creates the Azure-services firewall rule (`0.0.0.0`) only while private endpoints are disabled; database access still requires Microsoft Entra authentication and the API managed identity's contained database user. Production disables SQL public access and uses Private Link.

`prod` uses private PaaS endpoints, custom-VNet injection, explicit NAT egress, and a scalable replica range:

```text
enablePrivateEndpoints: true
containerAppMinReplicas: 2
containerAppMaxReplicas: 10
enableFrontDoorImageDelivery: true
```

Production application deployment uses a GitHub-hosted Linux runner. The workflow temporarily allowlists that runner's `/32` address on ACR and Azure SQL, performs the image push and migration, and restores private-only access in unconditional cleanup steps. The final Bicep deployment also enforces disabled public access.

`Shopping.Web` is the only public application endpoint. It calls `Shopping.Api` through internal Container Apps service discovery, and the API still validates the delegated Entra access token. The runtime images enable ASP.NET Core forwarded headers so HTTPS redirection observes the original scheme after Container Apps TLS termination.

Production image delivery uses Azure Front Door Premium:

```text
Browser -> Front Door Premium -> Private Link -> Blob Storage product-images container
```

All Azure-hosted environments keep the image container private and return shared short-lived SAS query strings. Dev and test return direct Blob Storage URLs; production returns Front Door URLs. The default SAS lifetime is 10 minutes. Front Door caches by full query string so all app users share cache entries during the same SAS window.

The Front Door private endpoint connection to the Storage account may require approval in the target subscription after the first deployment.

## Pipeline Behaviour

The `infra` workflow:

- builds all Bicep parameter files on pull requests and pushes to `master`,
- automatically reconciles `dev` after IaC changes reach `master`,
- deploys `test` or `prod` only from manual workflow dispatch,
- validates and runs `what-if` before every deployment,
- tears down a selected environment only from manual workflow dispatch,
- requires a typed teardown confirmation such as `destroy-dev`,
- deletes the environment resource group during teardown,
- purges soft-deleted Key Vaults after dev and test teardown; production vaults retain purge protection.

The `app` workflow:

- runs automatically for `dev` after the `infra` workflow succeeds on `master`,
- uses manual dispatch for `test` and `prod`,
- builds Web and API images tagged with the source commit SHA,
- pushes images to ACR using GitHub OIDC and Azure RBAC,
- obtains a short-lived Azure SQL access token,
- applies EF Core migrations and grants the API managed identity `db_datareader` and `db_datawriter` using its client ID as the Azure SQL service-principal SID,
- updates both Container Apps through Bicep, verifies the API revision is healthy, and calls the public Web `/healthz` endpoint.

## First Deployment

1. Complete bootstrap and verification.
2. Merge the reviewed IaC changes to `master`.
3. The `infra` workflow automatically creates or reconciles the development resources.
4. After `infra` succeeds, the `app` workflow builds, migrates, and deploys the first runnable images.
5. Copy the Web origin from the workflow summary to `ExternalId.PublicWebBaseUrls.dev` and rerun the External ID bootstrap stage.
6. Confirm health checks and customer sign-in before promoting the same commit through test and production.

For an existing installation, reconcile the GitHub bootstrap stage before merging workflow changes that introduce new environment variables or required checks. This prevents the automatic development deployment from starting with stale GitHub configuration.

When migrating an existing installation from App Service, rerun `Initialize-ShoppingBootstrap.ps1 -Stage AzureIdentity` before deployment. This registers the `Microsoft.App` and `Microsoft.ManagedIdentity` resource providers required by the Container Apps baseline.

See the [Shopping CI/CD Deployment Playbook](../docs/deployment-playbook.md) for promotion, rollback, failure recovery, and teardown procedures.

Use `what-if` output as the reviewable deployment plan before approving production changes.

To deploy:

```text
Actions -> infra -> Run workflow
operation: deploy
environmentName: dev, test, or prod
```

To deploy application images manually:

```text
Actions -> app -> Run workflow
environmentName: dev, test, or prod
migrateDatabase: true
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
