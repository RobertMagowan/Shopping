# End-To-End Deployment Runbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a canonical, technically detailed guide from empty Azure preparation through bootstrap, first deployment, recurring CI/CD, teardown, and verified rebuild.

**Architecture:** Add one canonical lifecycle runbook and retain focused documents as references. Validate the instructions by destroying only repository-managed Azure environment resources, rebuilding with the modular templates, deploying the application, and recording verified outcomes without committing installation-specific credentials.

**Tech Stack:** Markdown, PowerShell 7, Azure CLI, GitHub CLI, GitHub Actions, Microsoft Entra External ID, Azure Bicep, Container Apps, Azure SQL, Managed Redis, Key Vault, ACR.

## Global Constraints

- Do not commit tenant IDs, subscription IDs, client secrets, passwords, access tokens, or local bootstrap state.
- State the active tenant/subscription/repository context for every administrative command.
- Distinguish manual External ID tenant/user-flow steps from script-owned configuration.
- Document both automatic merge-driven deployment and manual workflow dispatch.
- Destroy only resource groups matching the configured Shopping installation and environment.
- Do not delete bootstrap identities, app registrations, GitHub environments, or the External ID tenant.
- Stop all Shopping processes and verify local ports `7202`, `7262`, `5044`, and `5140` are free before handoff.

---

### Task 1: Create The Canonical Runbook

**Files:**
- Create: `docs/end-to-end-deployment-runbook.md`

- [ ] **Step 1: Document scope and architecture**

Include the browser-to-Web BFF-to-internal-API flow, Azure resource topology, three environment model, managed identities, and ownership table for operator, bootstrap, Bicep, GitHub Actions, and manual portal tasks.

- [ ] **Step 2: Document prerequisites and collected values**

Provide commands for `git`, `pwsh`, `az`, `gh`, `.NET 10`, Docker, Azure CLI account context, and GitHub authentication. Explain required Azure/Entra/GitHub permissions, Container Apps quota, immutable tenant geography, naming, and cost-sensitive resources.

- [ ] **Step 3: Document empty-tenant preparation**

Describe manual External ID tenant creation in the Entra admin center, the required Azure subscription linkage, switching directories, and recording tenant/domain/authority values. Explicitly state that bootstrap does not create the tenant itself.

- [ ] **Step 4: Document repository and bootstrap setup**

Show repository creation/import, cloning, local ignored configuration, `-WhatIf`, tenant switching, secure SQL password input, `-RotateWebClientSecret`, `-GrantAdminConsent`, `-ConfigureLocalUserSecrets`, GitHub configuration, branch rules, and read-only verification.

- [ ] **Step 5: Document manual External ID tasks**

Explain customer user flow creation, adding Shopping.Web, identity-provider selection, local customer bootstrap Admin creation, temporary password handling, app-role assignment, and the distinction between B2B tenant administrator and customer directory object.

- [ ] **Step 6: Document first deployment and reconciliation**

Explain infrastructure/application workflow separation, `bootstrap` image behavior, ACR push, SQL migration, Container Apps creation, `/signin-oidc` callback reconciliation, `/healthz`, and the current self-sign-up `Customer` role limitation.

- [ ] **Step 7: Document feature-to-production delivery**

Cover feature branch, pull request, required checks, review resolution, merge to `master`, automatic dev deployment, manual test promotion, production approval, self-hosted runner requirements, rollback, and teardown.

### Task 2: Synchronize Focused Guides

**Files:**
- Modify: `README.md`
- Modify: `docs/bootstrap.md`
- Modify: `docs/entra-external-id-setup.md`
- Modify: `docs/deployment-playbook.md`
- Modify: `infra/README.md`

- [ ] **Step 1: Add the canonical entry point**

Link `docs/end-to-end-deployment-runbook.md` from `README.md` and the introduction of every focused guide.

- [ ] **Step 2: Correct identity guidance**

Update the Entra guide so the bootstrap Admin is a local customer account, not merely the external-tenant B2B administrator. Document that self-service users do not automatically receive the `Customer` app role in the current implementation.

- [ ] **Step 3: Document modular infrastructure**

Replace the single environment-module description with a module dependency graph and concise responsibility table. Preserve the statement that `main.bicep` is subscription-scoped and `environment.bicep` orchestrates resource-group modules.

- [ ] **Step 4: Expand recovery guidance**

Add symptom/cause/recovery entries for execution policy, wrong tenant, GitHub CLI state, OIDC casing, missing GitHub values, Container Apps quota, Managed Redis delay/failure, Key Vault purge protection, SQL migration, `/healthz`, callback correlation, and user-flow/login errors.

### Task 3: Validate Documentation And Bootstrap

**Files:**
- Verify only.

- [ ] **Step 1: Scan for broken local links and forbidden sensitive values**

Run a PowerShell link check over Markdown links targeting repository files, then run:

```powershell
rg -n "ClientSecret|SQL_ADMINISTRATOR_PASSWORD|accessToken|password=" README.md docs infra/README.md
git diff --check
```

Expected: only explanatory names/placeholders, no credential values, and no whitespace errors.

- [ ] **Step 2: Run bootstrap regression and verifier**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\Test-BootstrapShared.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ShoppingBootstrap.ps1 -ConfigPath .\scripts\bootstrap.config.psd1
```

Expected: helper tests pass; automated bootstrap areas pass; user-flow remains explicitly manual.

### Task 4: Publish The Branch And Pass Pull-Request Checks

**Files:**
- Git/GitHub operation only.

- [ ] **Step 1: Push the branch and open a pull request**

```powershell
git push -u origin codex/end-to-end-deployment-runbook
gh pr create --base master --head codex/end-to-end-deployment-runbook --title "refactor(infra): modularize Bicep deployment" --body-file .\pr-description.md
```

- [ ] **Step 2: Verify required checks and review comments**

```powershell
gh pr checks --watch
gh pr view --comments
```

Use the `gh-fix-ci` and `gh-address-comments` skills for failures or actionable review feedback. Do not merge until CI, CodeQL, container builds, and all three infrastructure static validations pass.

### Task 5: Capture The Existing Azure Baseline

**Files:**
- Do not write credentials or identifiers to tracked files.

- [ ] **Step 1: Verify account and enumerate repository-owned environments**

```powershell
az account show --output table
az group list --query "[?starts_with(name, 'rg-shopping-')].[name,location,properties.provisioningState]" --output table
```

Cross-check every candidate against `WORKLOAD_NAME`, `DEPLOYMENT_INSTANCE`, environment, location, and tags before destructive action.

- [ ] **Step 2: Capture runtime health and image state**

For each confirmed resource group, query Container Apps names, FQDNs, active revisions, image tags, Redis state, SQL state, and Key Vault name. Call the public Web `/healthz` endpoint and record only non-secret operational evidence in the PR or workflow run notes.

### Task 6: Destroy Repository-Managed Development Infrastructure

**Files:**
- GitHub workflow operation only.

- [ ] **Step 1: Dispatch the supported destroy workflow**

```powershell
gh workflow run infra.yml --ref master -f operation=destroy -f environmentName=dev -f location=uksouth -f confirmDestroy=destroy-dev
```

- [ ] **Step 2: Watch completion and verify deletion**

```powershell
$runId = gh run list --workflow infra.yml --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --exit-status
$workloadName = gh variable get WORKLOAD_NAME --env dev
$deploymentInstance = gh variable get DEPLOYMENT_INSTANCE --env dev
$resourceGroupName = "rg-$workloadName-$deploymentInstance-dev-uksouth"
az group exists --name $resourceGroupName
```

Expected: workflow success and `false`. Verify dev/test Key Vault purge behavior without deleting unrelated soft-deleted vaults.

### Task 7: Rebuild Infrastructure And Deploy The Application

**Files:**
- GitHub workflow and local ignored bootstrap configuration only.

- [ ] **Step 1: Deploy modular infrastructure from the reviewed branch**

```powershell
gh workflow run infra.yml --ref codex/end-to-end-deployment-runbook -f operation=deploy -f environmentName=dev -f location=uksouth
```

Watch the run to completion. Inspect validation, `what-if`, and deployment output. Azure Managed Redis may take tens of minutes; do not launch a duplicate deployment while it is still provisioning.

- [ ] **Step 2: Deploy application images and database migration**

```powershell
gh workflow run app.yml --ref codex/end-to-end-deployment-runbook -f environmentName=dev -f migrateDatabase=true
```

Watch image build/push, temporary SQL firewall creation/removal, EF Core migration, managed-identity grants, Container Apps deployment, API revision health, and Web `/healthz`.

- [ ] **Step 3: Reconcile the Web callback**

If the FQDN changed, update ignored `ExternalId.PublicWebBaseUrls.dev` and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Initialize-ShoppingBootstrap.ps1 -ConfigPath .\scripts\bootstrap.config.psd1 -Stage ExternalId
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ShoppingBootstrap.ps1 -ConfigPath .\scripts\bootstrap.config.psd1
```

### Task 8: Verify The Rebuilt Environment

**Files:**
- Verify only.

- [ ] **Step 1: Verify Azure resource and application state**

Confirm the resource group exists, all expected resource providers report `Succeeded`, Redis is running, both Container Apps have active healthy revisions, API ingress is internal, Web ingress is external, and the deployed image tag matches the branch commit SHA.

- [ ] **Step 2: Verify HTTP and authentication routing**

Call the Web `/healthz` endpoint and a protected route. Confirm the protected route challenges against the configured `ciamlogin.com` authority with the deployed `/signin-oidc` callback. Do not print tokens or cookies.

- [ ] **Step 3: Verify data and image paths**

Confirm EF migrations exist in Azure SQL, API managed identity runtime access is granted, catalog data can be read through the BFF, product images use short-lived shared SAS URLs, and the image response succeeds.

- [ ] **Step 4: Record verified outcomes in the runbook**

Add durations, observed resource states, and any recovery needed as generalized operational guidance. Do not add the installation's IDs, secrets, or passwords.

### Task 9: Final Repository Verification And Handoff

**Files:**
- Verify only.

- [ ] **Step 1: Run all local checks**

Run the complete Bicep, PowerShell, .NET build, and .NET test command set from the modular Bicep plan.

- [ ] **Step 2: Stop Shopping processes and verify ports**

Use the cleanup command in `AGENTS.md`, then verify ports `7202`, `7262`, `5044`, and `5140` have no listeners.

- [ ] **Step 3: Review the final diff against both specifications**

Confirm every runbook topic, module boundary, security constraint, deployment check, and failure-recovery lesson is represented. Report any remaining manual user-flow or customer-role limitation explicitly.
