# Bootstrap Administrator Provisioning Design

## Objective

Make an empty Microsoft Entra External ID tenant immediately usable by creating the first Shopping customer administrator during bootstrap. The operator supplies an email address; the script creates or adopts the corresponding local customer account, assigns the Shopping `Admin` application role, and never persists the temporary password.

This changes application authorization only. It does not grant a Microsoft Entra directory role to the customer account.

## Current Behavior

`Initialize-ShoppingBootstrap.ps1` can list tenant users and accept an existing user object ID. `bootstrap-entra-apps.ps1` then assigns that object to the `Admin` role on the Web and API enterprise applications. The account must already exist, which leaves a manual portal step in an otherwise repeatable empty-tenant bootstrap.

## Chosen Approach

Integrate local-account provisioning into the existing `ExternalId` stage rather than adding a second top-level script.

- Add `ExternalId.BootstrapAdminEmail` to bootstrap configuration.
- When `-PromptForExternalIdValues` is used, prompt the operator to enter, keep, or change this email address.
- Resolve the email against local `emailAddress` identities in the configured external tenant.
- Adopt a single matching account without changing its password.
- Create the account only when no match exists.
- Assign `Admin` to both Shopping.Web and Shopping.Api through the existing idempotent role-assignment function.
- Store the resolved object ID and normalized email in ignored bootstrap state.

The existing `BootstrapAdminUserObjectId` input remains a compatibility path for current installations. If both email and object ID are supplied, they must identify the same user or bootstrap fails without changing assignments. New examples and documentation use the email-based flow.

## Interactive Experience

The operator runs the existing orchestrator with `-Stage ExternalId` or `-Stage All` and `-PromptForExternalIdValues`. The prompt asks for the application administrator's sign-in email. The email is trimmed, normalized for comparison, and validated before any Graph request.

If the account is created, the script prints:

- the normalized sign-in email;
- the generated temporary password exactly once;
- a warning that the value is not recoverable from bootstrap state;
- an instruction to change the password at first sign-in.

No password is generated or printed during `-WhatIf`. Existing accounts do not have their passwords reset and produce no password output.

Creating the account requires `-PromptForExternalIdValues` in an interactive host. A non-interactive run may adopt an account named by configuration or state, but fails with a remediation command when that account does not yet exist. This prevents the temporary password from entering CI logs.

## Local Account Creation

The script uses Microsoft Graph `POST /v1.0/users` with:

- `accountEnabled = true`;
- a stable display name of `Shopping Bootstrap Administrator`;
- `creationType = LocalAccount`;
- one identity with `signInType = emailAddress`, the configured external tenant domain as `issuer`, and the prompted email as `issuerAssignedId`;
- `mail` set to the prompted email;
- `passwordPolicies = DisablePasswordExpiration`;
- a generated password profile with `forceChangePasswordNextSignIn = true`.

The Graph request body is sent directly from process memory with `Invoke-RestMethod`. The password is never written to a temporary file or placed in command-line arguments.

## Password Generation And Handling

Generate a 24-character temporary password with `RandomNumberGenerator`. The result must include at least one uppercase letter, lowercase letter, digit, and permitted symbol. Character selection and shuffling both use cryptographically secure random bytes; `System.Random` is not used.

The plaintext exists only in process memory. It is not written to bootstrap configuration, bootstrap state, user secrets, GitHub variables, GitHub secrets, Key Vault, temporary files, or application logs. The operation is interactive-only when it must create an account, preventing a temporary password from being exposed in GitHub Actions logs. Operators should not run the creation step under PowerShell transcription or screen sharing.

## Idempotency And Failure Handling

User resolution compares `issuer`, `signInType`, and `issuerAssignedId` case-insensitively.

- Zero matches: create the account after `ShouldProcess` approval.
- One match: adopt it and preserve its password.
- Multiple matches: stop and require manual directory cleanup.
- Configured object ID disagrees with the email match: stop before assigning roles.
- Graph creation succeeds but a role assignment fails: record enough non-secret identity state to make the rerun adopt the user and retry only missing assignments.
- Graph creation returns a duplicate or ambiguous failure: stop and surface the error. A deliberate rerun adopts an exact existing identity without resetting its password.

Bootstrap validates that Azure CLI is signed into the configured External ID tenant. The signed-in operator must have permission to create external users and assign application roles. Permission failures include the tenant, requested email, operation, and remediation guidance without exposing the generated password.

## State And Verification

Bootstrap state records `bootstrapAdminEmail` and `bootstrapAdminUserObjectId`. `Test-ShoppingBootstrap.ps1` verifies:

- the object exists;
- it has the expected local email identity and is enabled;
- its object ID matches bootstrap state;
- both Web and API `Admin` role assignments exist.

The verifier never reads or validates a password. Password-change completion remains an interactive sign-in check because Microsoft Graph does not expose the password.

## Tests And Documentation

PowerShell tests cover password composition, exact user matching, adoption, duplicate rejection, `-WhatIf`, no password persistence, legacy object-ID compatibility, and idempotent role assignment. Existing bootstrap tests and the full solution build remain required.

Update the bootstrap guide, Entra setup guide, deployment playbook, end-to-end deployment runbook, example configuration, and contributor guidance where command behavior changes. The documents must distinguish this Shopping application administrator from a Microsoft Entra tenant administrator and explain that the temporary password is displayed once.

Documentation accuracy is an acceptance criterion:

- Replace the existing manual bootstrap-admin object-ID procedure with the email-driven creation and adoption flow.
- Show the exact final parameters for interactive creation, `-WhatIf`, reruns, and non-interactive adoption.
- State the required External ID directory permissions and tenant context.
- Explain that creation does not modify the customer user flow or assign a Microsoft Entra directory role.
- Explain how generated credentials are displayed, changed, and deliberately not recovered.
- Preserve the correct `/healthz`, environment promotion, teardown, and redeployment instructions already verified during the deployment exercise.
- Validate documented commands against script help, parameter definitions, and automated tests before merge.

## Out Of Scope

- Automatically creating the External ID tenant or customer user flow.
- Assigning Microsoft Entra directory roles to the customer administrator.
- Sending the temporary password by email or storing it for later retrieval.
- Automatically assigning `Customer` to every self-service sign-up.
