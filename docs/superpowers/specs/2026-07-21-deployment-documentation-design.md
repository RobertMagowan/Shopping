# End-to-End Deployment Documentation Design

## Objective

Create a technically detailed, human-readable deployment guide that takes a new operator from an empty Azure subscription and a cloned Shopping repository to verified `dev`, `test`, and `prod` deployments. The guide must also explain the normal delivery lifecycle from a feature branch through pull-request validation, merge to `master`, automatic development deployment, and controlled promotion.

The documentation must describe both the preferred automated path and the equivalent manual workflow entry points. It must not embed credentials or identifiers from the current installation.

## Audience And Assumptions

The reader has a software or cloud engineering background but does not know this repository. Commands must be complete and accompanied by:

- the account, tenant, subscription, directory, or repository context in which they run;
- the resources or configuration they create;
- the expected outcome and verification method;
- common failure causes and recovery actions;
- relevant security and cost implications.

The guide may assume familiarity with Git, PowerShell, Azure, Entra, GitHub Actions, containers, and .NET terminology, but must explain repository-specific behavior.

## Documentation Structure

Add `docs/end-to-end-deployment-runbook.md` as the canonical entry point. It will cover:

1. Deployment architecture and ownership boundaries.
2. Required accounts, permissions, tools, values, quotas, and operator decisions.
3. Manual creation of the Azure subscription context and Entra External ID external tenant.
4. GitHub repository creation/import and local clone preparation.
5. Bootstrap configuration, preview, application, and verification.
6. Manual customer user-flow, identity-provider, and bootstrap-administrator setup.
7. First infrastructure and application deployment through GitHub Actions.
8. The manual deployment alternative using workflow dispatch.
9. Post-deployment callback reconciliation and authentication verification.
10. The feature-branch-to-production delivery lifecycle.
11. Database migration, managed identity, networking, health, and runtime verification.
12. Rollback, teardown, cost control, troubleshooting, and handover checklists.

Update the focused references rather than duplicating their complete content:

- `docs/bootstrap.md`: bootstrap ownership, exact stage ordering, customer bootstrap administrator, execution-policy recovery, and verification.
- `docs/entra-external-id-setup.md`: tenant creation, customer versus administrative identities, customer user flow, self-service sign-up, and role-assignment limitations.
- `docs/deployment-playbook.md`: recurring CI/CD operation, first-deployment reconciliation, workflow behavior, and recovery.
- `infra/README.md`: deployed resources, first-deployment topology, runtime identity, Key Vault, Redis, SQL, ingress, and infrastructure-specific failure behavior.
- Repository `README.md`: link the canonical runbook prominently.

## Manual And Automated Boundaries

The runbook must not imply that the scripts create an Entra External ID tenant. The operator creates the external tenant in the Microsoft Entra admin center, selects its immutable geography and domain, and links it to an Azure subscription. The bootstrap then manages the Shopping Web/API registrations, service principals, app roles, API scope, consent, redirect URIs, bootstrap administrator assignment, GitHub environments, GitHub OIDC identity, Azure RBAC, and branch ruleset.

Customer user-flow creation and identity-provider selection remain manual because the bootstrap identity does not have user-flow administration permissions. The guide must distinguish:

- the workforce/home-tenant operator;
- the external-tenant administrator;
- a local customer account used as the first Shopping administrator;
- ordinary self-service customer accounts.

It must state that a B2B administrative identity and a customer identity using the same email address are separate directory objects. Temporary passwords must be copied directly to the intended operator and never written to repository files, logs, or documentation.

## Deployment Narrative

The preferred path is:

```text
manual tenant/repository preparation
  -> bootstrap preview
  -> bootstrap apply
  -> bootstrap verification
  -> manual user-flow verification
  -> feature branch and pull request
  -> required CI, CodeQL, and Bicep checks
  -> merge to master
  -> automatic dev infrastructure reconciliation
  -> automatic image build, migration, and app deployment
  -> callback reconciliation
  -> dev verification
  -> manual test promotion
  -> approved production promotion
```

The guide will also show how to invoke `infra.yml` and `app.yml` manually, when that is appropriate, and why infrastructure and application deployment are separate workflows.

## Troubleshooting Coverage

Use symptom, diagnosis, cause, recovery, and prevention entries for the failures observed during deployment:

- wrong Azure or External ID tenant context;
- PowerShell execution policy blocking scripts;
- GitHub CLI authentication or stale desktop integration state;
- incorrect repository casing in OIDC subjects;
- missing GitHub environment variables, secrets, or production protection;
- Container Apps regional quota failures;
- slow or failed Azure Managed Redis provisioning;
- Key Vault purge-protection and soft-deleted-name conflicts;
- infrastructure path filtering and chained application deployment behavior;
- SQL firewall, migration, token, or managed-identity permission failures;
- wrong health route (`/health` instead of `/healthz`);
- incorrect OpenID Connect redirect URI and correlation failures;
- tenant administrator used as a customer login;
- missing customer user flow, application assignment, sign-up link, or identity provider;
- absent `Customer` app-role assignment after self-service sign-up;
- internal API reachability and container revision failures.

The current customer-role behavior must be documented as a limitation unless code changes implement authenticated-user baseline access. Documentation must not claim that self-service sign-up automatically assigns an Entra app role.

## Verification Standard

All commands and file paths must match the repository. Documentation validation includes Markdown/link inspection, bootstrap regression tests, Bicep compilation, .NET build/tests where practical, and confirmation that no secrets or installation-specific credentials were introduced. All Shopping processes must be stopped before handing control back.
