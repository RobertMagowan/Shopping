# Bootstrap Administrator Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create or adopt the first Shopping customer administrator by email during interactive External ID bootstrap, generate a one-time temporary password for new accounts, and deploy the verified result from `master`.

**Architecture:** Keep orchestration in `Initialize-ShoppingBootstrap.ps1`, application registration and role assignment in `bootstrap-entra-apps.ps1`, and reusable Graph/password operations in a focused `bootstrap-external-id-admin.ps1` helper. Store only the normalized email and object ID in ignored bootstrap state. CI runs deterministic PowerShell tests with Graph calls replaced by in-process fakes.

**Tech Stack:** Windows PowerShell 5.1+, PowerShell 7, Azure CLI, Microsoft Graph v1.0, GitHub Actions, Bicep, .NET 10.

## Global Constraints

- Creating an administrator requires `-PromptForExternalIdValues` in an interactive host.
- Generate a 24-character password with `RandomNumberGenerator`; never use `System.Random`.
- Never persist the temporary password in configuration, state, GitHub, Key Vault, user secrets, or logs.
- Existing accounts are adopted without resetting their passwords.
- Preserve `BootstrapAdminUserObjectId` as a compatibility input and fail when it disagrees with the email identity.
- Assign only Shopping Web/API `Admin` app roles, never a Microsoft Entra directory role.
- All documented commands must match final parameters and verified behavior.
- Keep the existing Bicep interface and deployment workflow contracts unchanged.

---

### Task 1: External ID Administrator Helper

**Files:**
- Create: `scripts/bootstrap-external-id-admin.ps1`
- Create: `scripts/tests/Test-BootstrapExternalIdAdmin.ps1`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `Normalize-BootstrapAdminEmail`, `New-BootstrapAdminTemporaryPassword`, `Get-BootstrapAdminLocalUser`, and `New-BootstrapAdminLocalUser`.
- Uses: an in-memory `Invoke-RestMethod` Graph helper so the password is never serialized to disk or a command-line argument.

- [ ] **Step 1: Write failing password and identity-resolution tests**

The test dot-sources `bootstrap-shared.ps1` and the new helper. It generates 100 passwords and requires length 24 plus uppercase, lowercase, digit, and symbol categories. Replace `Invoke-BootstrapAdminGraphJson` with a fake returning local identities, then assert exact case-insensitive issuer/email matching, no match, and duplicate-match rejection.

```powershell
$passwords = 1..100 | ForEach-Object { New-BootstrapAdminTemporaryPassword }

foreach ($password in $passwords) {
    if ($password.Length -ne 24 -or
        $password -cnotmatch '[A-Z]' -or
        $password -cnotmatch '[a-z]' -or
        $password -notmatch '[0-9]' -or
        $password -notmatch '[!@#$%*+\-_=]') {
        throw "Generated password does not satisfy the bootstrap policy."
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\Test-BootstrapExternalIdAdmin.ps1
```

Expected: failure because `bootstrap-external-id-admin.ps1` or its functions do not exist.

- [ ] **Step 3: Implement cryptographic generation and Graph helpers**

`Normalize-BootstrapAdminEmail` trims, validates with `System.Net.Mail.MailAddress`, and lowercases for comparison. `New-BootstrapAdminTemporaryPassword` guarantees each required category, fills to 24 characters, and performs a Fisher-Yates shuffle using unbiased bytes from `RandomNumberGenerator`.

`Get-BootstrapAdminLocalUser` requests `id,accountEnabled,displayName,mail,identities` and matches all three identity fields: `signInType=emailAddress`, configured domain issuer, and email issuer-assigned ID. It returns null or one user and throws for duplicates.

`New-BootstrapAdminLocalUser` sends:

```powershell
@{
    accountEnabled = $true
    creationType = 'LocalAccount'
    displayName = 'Shopping Bootstrap Administrator'
    identities = @(@{
        signInType = 'emailAddress'
        issuer = $Domain
        issuerAssignedId = $Email
    })
    mail = $Email
    passwordProfile = @{
        password = $TemporaryPassword
        forceChangePasswordNextSignIn = $true
    }
    passwordPolicies = 'DisablePasswordExpiration'
}
```

- [ ] **Step 4: Verify GREEN and run all helper tests**

Run both scripts under Windows PowerShell and PowerShell 7 when available. Expected: all helper tests pass and no password value appears in captured Graph URIs or state fixtures.

- [ ] **Step 5: Run all bootstrap tests in CI**

Change the CI step to:

```powershell
Get-ChildItem ./scripts/tests/Test-*.ps1 | ForEach-Object {
    & $_.FullName
    if (-not $?) { exit 1 }
}
```

- [ ] **Step 6: Commit**

```text
feat(auth): add External ID admin provisioning helpers
```

### Task 2: Orchestrator, Role Assignment, And State

**Files:**
- Modify: `scripts/Initialize-ShoppingBootstrap.ps1`
- Modify: `scripts/bootstrap-entra-apps.ps1`
- Modify: `scripts/bootstrap.config.example.psd1`
- Modify: `scripts/tests/Test-BootstrapExternalIdAdmin.ps1`

**Interfaces:**
- Consumes: Task 1 helper functions.
- Produces: `ExternalId.BootstrapAdminEmail`, `-BootstrapAdminEmail`, `-AllowBootstrapAdminCreation`, and pass-through `BootstrapAdminTemporaryPassword` as `SecureString`.

- [ ] **Step 1: Add failing orchestration assertions**

Assert that a configured email is normalized, interactive creation is allowed only with `-PromptForExternalIdValues`, legacy object-ID-only runs remain valid, conflicting email/object ID fails before role assignment, and `-WhatIf` creates no password or user.

- [ ] **Step 2: Run tests and verify RED**

Expected: failure because the orchestrator and child script do not accept email-based administration.

- [ ] **Step 3: Replace user selection with email prompting**

Read `ExternalId.BootstrapAdminEmail` safely when older configuration omits it. In prompt mode, ask:

```text
Bootstrap application administrator email
```

Pass normalized email, compatibility object ID, and `AllowBootstrapAdminCreation=$PromptForExternalIdValues` to `bootstrap-entra-apps.ps1`.

- [ ] **Step 4: Resolve, create, checkpoint, and assign**

In `bootstrap-entra-apps.ps1`, dot-source the helper, adopt or create the local account, validate any compatibility object ID, checkpoint `bootstrapAdminEmail` and `bootstrapAdminUserObjectId`, then call the existing idempotent Web and API role assignments. Creation without the interactive flag throws a command showing the required rerun.

Return a generated temporary password as `SecureString`. The orchestrator converts it only long enough to print the email, password, and first-sign-in change instruction, then clears the BSTR. Do not include it in state or subsequent GitHub configuration maps.

- [ ] **Step 5: Verify GREEN and inspect state**

Run helper tests and an External ID `-WhatIf`. Search generated test state and git diff for known password fixtures. Expected: identifiers only, no credentials.

- [ ] **Step 6: Commit**

```text
feat(auth): provision bootstrap administrator by email
```

### Task 3: Bootstrap Verification And Accurate Playbooks

**Files:**
- Modify: `scripts/Test-ShoppingBootstrap.ps1`
- Modify: `docs/bootstrap.md`
- Modify: `docs/entra-external-id-setup.md`
- Modify: `docs/deployment-playbook.md`
- Modify: `docs/end-to-end-deployment-runbook.md`
- Modify: `scripts/bootstrap.config.example.psd1`
- Modify: `AGENTS.md` only if contributor commands change.

**Interfaces:**
- Consumes: bootstrap state fields from Task 2.
- Produces: verified email identity and role-assignment result.

- [ ] **Step 1: Add failing verifier tests or structural assertions**

Require the verifier to fetch the recorded user, confirm it is enabled, match the local email identity, and verify both `Admin` assignments. It must not attempt to inspect a password.

- [ ] **Step 2: Implement verification**

Resolve email from configuration or state, fetch `GET /users/{id}?$select=id,accountEnabled,identities`, and report separate details for identity mismatch, disabled account, and missing role assignments.

- [ ] **Step 3: Replace outdated documentation**

Replace manual object-ID instructions with the exact interactive command, expected one-time output, forced password change, idempotent rerun behavior, legacy compatibility, required tenant role, and distinction between application `Admin` and Entra directory administration. Keep the established `/healthz`, promotion, teardown, and clean-rebuild guidance intact.

- [ ] **Step 4: Validate documentation**

Compare every command against `Get-Help`, parameter declarations, workflow inputs, and actual filenames. Run the Markdown local-link checker used for the deployment runbook and scan for live installation IDs or secret values.

- [ ] **Step 5: Commit**

```text
docs(auth): document bootstrap administrator workflow
```

### Task 4: Complete PR Review And Merge

**Files:**
- Modify: `infra/modules/sql.bicep`
- Modify: `infra/tests/Test-BicepModules.ps1`

- [ ] **Step 1: Commit the validated SQL review fix**

Keep SQL login/password properties in dev only and set inline `azureADOnlyAuthentication` for test/prod. Run the structural test, Bicep build, and all parameter builds before committing.

- [ ] **Step 2: Run full local verification**

Run bootstrap tests, Bicep tests/builds, `dotnet restore`, Release build, Release tests, migration model check, `git diff --check`, documentation link checks, and secret/installation-ID scans.

- [ ] **Step 3: Push and resolve review**

Push the feature branch, reply to and resolve the SQL review thread, wait for required CI/CodeQL/container/Bicep checks, and address only validated findings.

- [ ] **Step 4: Merge PR to `master`**

Use the repository merge policy, confirm the merge commit is on `master`, and wait for automatic dev infrastructure/app workflows to settle before issuing another deployment.

### Task 5: Clean Dev Deployment And Administrator Handoff

**Files:**
- No repository changes expected unless deployment reveals a verified defect.

- [ ] **Step 1: Deploy infrastructure from `master`**

Dispatch `infra.yml` with `operation=deploy`, `environmentName=dev`, and `location=uksouth`. Wait for Managed Redis and all Bicep modules to complete.

- [ ] **Step 2: Deploy application images and database**

Dispatch `app.yml` for dev from the same `master` SHA with migrations enabled. Verify Web/API revisions, `/healthz`, managed-identity SQL migration, product seed data, and image delivery.

- [ ] **Step 3: Reconcile callback and bootstrap administrator**

Update ignored `ExternalId.PublicWebBaseUrls.dev` if the Web FQDN changed. The operator then runs the interactive External ID stage locally, enters the administrator email at the prompt, records the generated temporary password, and changes it at first sign-in.

- [ ] **Step 4: Verify bootstrap and sign-in**

Run `Test-ShoppingBootstrap.ps1`, confirm both app roles, complete a browser sign-in, and verify the administrator and product-management pages authorize correctly.

- [ ] **Step 5: Stop local processes**

Stop Shopping processes and verify ports `7202`, `7262`, `5044`, and `5140` are free.
