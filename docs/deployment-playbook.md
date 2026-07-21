# Shopping CI/CD Deployment Playbook

This playbook covers recurring delivery after repository bootstrap. Start with the [end-to-end deployment runbook](end-to-end-deployment-runbook.md) for an empty subscription and first deployment. Use the [bootstrap playbook](bootstrap.md) for one-time GitHub, Azure, and Entra configuration, and [infra/README.md](../infra/README.md) for the Bicep resource reference.

## Preconditions

Before deploying:

- `Test-ShoppingBootstrap.ps1` passes all automated checks.
- Existing installations have rerun `Initialize-ShoppingBootstrap.ps1 -Stage AzureIdentity` to register `Microsoft.App` and `Microsoft.ManagedIdentity`.
- Azure Container Apps Consumption quota is available in the target region.
- The customer user flow and identity providers have been verified manually.
- The pull request has all required status checks.
- Production has a VNet-connected Linux runner labelled `self-hosted`, `linux`, and `shopping-prod`.
- Production public ingress, DNS, certificate, and External ID callback configuration are complete before customer testing.

## Pipeline Map

| Workflow | Purpose | Automatic behavior | Manual behavior |
| --- | --- | --- | --- |
| `ci.yml` | Restore, build, test, and validate both container images | Pull requests and pushes to `master` | Any selected ref |
| `codeql.yml` | C# security analysis | Pull requests, pushes to `master`, and weekly | Any selected ref |
| `infra.yml` | Validate, plan, deploy, or destroy Bicep infrastructure | Validate pull requests; reconcile `dev` when IaC changes reach `master` | Deploy or destroy `dev`, `test`, or `prod` |
| `app.yml` | Build and push images, migrate SQL, deploy the image tag, and run health checks | Deploy `dev` after a successful `infra` push workflow | Deploy `dev`, `test`, or `prod` |

The application workflow runs after every successful `infra` workflow caused by a push to `master`. For a code-only merge, the infrastructure job is skipped but the development application is still deployed.

## Pull Request Flow

1. Push a feature branch and open a pull request to `master`.
2. Review `ci-build`, `ci-test`, `container-build`, `CodeQL`, and all three `infra-static-validation-*` checks.
3. Review Bicep and configuration changes for environment impact. Pull requests never deploy infrastructure or application images.
4. Merge only when required checks pass and review threads are resolved.

When a workflow change introduces a GitHub environment variable, secret, or required check, reconcile the GitHub bootstrap stage before merging it.

## Development Deployment

Merging to `master` starts the normal development path:

```text
push to master
  -> infra validation
  -> dev IaC reconciliation when IaC changed
  -> dev application image build and deployment
  -> SQL migration
  -> Web and API health checks
```

The first IaC deployment creates the platform resources and application identities without creating Container Apps. The chained application workflow pushes commit-SHA images, migrates SQL, and creates the runnable Container Apps. Copy the Web origin reported in the workflow summary to `ExternalId.PublicWebBaseUrls.dev`, then rerun the External ID bootstrap stage before testing sign-in.

If the automatic path did not run, use **Actions -> infra -> Run workflow**, select `deploy` and `dev`, then run **Actions -> app** for `dev` after infrastructure succeeds.

## Bootstrap Administrator Credential Step

GitHub Actions never asks for or displays the Shopping administrator email or password. Account creation is an operator-driven External ID bootstrap action, separate from Azure infrastructure and application deployment.

After the External ID applications exist, run locally while Azure CLI is signed in to the external tenant:

```powershell
.\scripts\Initialize-ShoppingBootstrap.ps1 `
  -ConfigPath .\scripts\bootstrap.config.psd1 `
  -Stage ExternalId `
  -PromptForExternalIdValues
```

Enter the email at `Bootstrap application administrator email`. If the local account is missing, the same terminal displays a generated 24-character temporary password exactly once. The administrator uses it for the first sign-in and Entra requires an immediate password change. Bootstrap stores only the normalized email and object ID.

Existing local accounts are adopted without password reset. A non-interactive run may adopt an account configured by email but cannot create one. The compatibility `BootstrapAdminUserObjectId` must agree with the local email identity when both are used.

Run `Test-ShoppingBootstrap.ps1` afterward. It verifies that the account is enabled, has the expected local identity, and is assigned to both application `Admin` roles. This Shopping role is not a Microsoft Entra directory role.

Do not put the generated password in GitHub secrets, Key Vault, configuration, state, workflow inputs, or deployment logs. This credential step is required once per installation, not once per deployment.

## Test Promotion

1. Confirm the development deployment and customer sign-in.
2. Run `infra` manually with `operation: deploy` and `environmentName: test`.
3. Review validation and `what-if` output, then wait for deployment success.
4. Run `app` manually for `test` with database migration enabled.
5. On the first deployment, reconcile the reported Web origin through `ExternalId.PublicWebBaseUrls.test` and the External ID bootstrap stage.
6. Verify `/healthz`, sign-in, catalog reads, image delivery, and role-protected operations.

Test has no deployment approval. Manual infrastructure runs do not automatically start the application workflow.

## Production Promotion

Production deployments must run from `master` and require approval.

1. Ensure the tested release commit is the current `master` commit.
2. Confirm the production runner is online and has private DNS and network access to ACR and Azure SQL.
3. Run `infra` manually for `prod`, review `what-if`, and approve the GitHub Environment deployment.
4. Complete any pending Front Door private-link approval.
5. Run `app` manually for `prod` with database migration enabled and approve the deployment.
6. On the first deployment, reconcile the reported Web origin through `ExternalId.PublicWebBaseUrls.prod` and the External ID bootstrap stage.
7. Verify health, authentication, authorization, catalog data, and image delivery through the public origin.

Infrastructure and application deployments require separate production approvals because they are separate workflow jobs.

## Database Migrations

The application workflow obtains a short-lived Azure SQL token and runs `Shopping.DatabaseMigrator`. It applies EF Core migrations, creates the API managed-identity database user, and grants runtime read/write roles.

- Do not run migrations during API startup.
- Keep schema changes compatible with the currently deployed application during rollout.
- A successful migration followed by a failed image deployment leaves the database ahead of the application. Fix or redeploy a compatible image; do not automatically roll the migration back.
- Rerunning the migrator is expected to be idempotent for already-applied EF migrations and grants.

## Failure Recovery

| Failure | Recovery |
| --- | --- |
| Static validation fails | Fix the branch; no Azure resources were changed. |
| IaC validation or `what-if` fails | Correct Bicep or environment configuration and rerun `infra`. |
| Container Apps reports a managed-environment or consumption-core quota error | In Azure **Quotas**, select **Azure Container Apps**, review the target region and subscription limits, and request only the required increase. Rerun `infra` after approval. |
| IaC deployment fails | Inspect the Azure deployment operation, fix the cause, and rerun. The application workflow will not start after a failed automatic IaC run. |
| Key Vault name exists in the deleted state | The infrastructure workflow recovers the purge-protected vault before ARM validation. Inspect the recovery operation if it still fails. |
| Azure rejects `Microsoft.Cache/redis` creation | Use the repository's Azure Managed Redis template; the retired Azure Cache for Redis resource type is not supported for new deployments. |
| Azure Managed Redis remains in `Creating` for tens of minutes | Wait while the resource and deployment operations show progress; do not dispatch an overlapping deployment. A first clean creation can take 20-40 minutes. |
| Azure Managed Redis ends in generic `OperationFailed` | Inspect the deployment operation, delete only the failed Redis resource when it is unusable, and perform one clean retry. Escalate repeated failures with Azure correlation details. |
| Image build or push fails | Correct the Docker build or ACR access and rerun `app`. |
| Migration fails | Inspect migrator output and SQL connectivity or permissions before rerunning. |
| Health check fails | Inspect Container Apps revisions, probes, logs, image-pull status, configuration, and private DNS. Rerun `app` after correction. |
| `/health` returns 404 | Use `/healthz`; both applications map that route. |
| Customer sign-in reports that the account does not exist | Use a customer identity, not the B2B object used to administer the external tenant. Confirm the customer flow contains Shopping.Web. |
| A new self-service customer receives 403 on cart | Assign the current `Customer` app role manually; sign-up does not automatically add role assignments. |

Use the workflow run URL and Azure deployment name from the logs as the primary incident record. Application Insights and Log Analytics contain runtime telemetry after the containers start.

## Rollback

Application images use immutable commit-SHA tags. The supported rollback path is:

1. Revert the faulty change through a pull request.
2. Merge the revert after required checks pass.
3. Allow development to deploy automatically, then promote the revert through test and production.

Do not change Container Apps image tags manually because the next Bicep deployment will reconcile them. Database rollback is not automated; use a deliberate forward-fix migration unless a reviewed database recovery plan requires otherwise.

For IaC rollback, revert the IaC commit through a pull request and inspect `what-if` before deployment. Never assume an ARM resource can be downgraded or recreated without data loss.

## Teardown

Run **Actions -> infra -> Run workflow** with:

```text
operation: destroy
environmentName: dev, test, or prod
confirmDestroy: destroy-<environment>
```

Teardown deletes the complete environment resource group, including SQL and Blob data. Production still requires approval. Key Vault uses purge protection, so a later deployment using the same deterministic vault name may require recovery of the soft-deleted vault; do not attempt to purge it as part of normal operations.

## APIM Versioning

APIM and Application Gateway are not implemented in the current baseline. When APIM is added, dev and test should update the current unreleased API revision. Create a new externally visible API version only when a previously released production contract must remain supported.
