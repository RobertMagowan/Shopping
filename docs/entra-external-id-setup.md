# Microsoft Entra External ID Portal Reference

The bootstrap scripts authoritatively manage the dedicated Shopping.Web and Shopping.Api registrations, including roles, scope, API permission, and redirect URIs. Start with the [end-to-end deployment runbook](end-to-end-deployment-runbook.md) for a new installation. Use this guide for explicitly manual external-tenant, user-flow, identity-provider, and user-assignment steps and as a portal reference for inspecting generated settings.

Do not make competing manual changes to script-owned application properties. Update `scripts/bootstrap.config.psd1`, preview the ExternalId stage with `-WhatIf`, and rerun it instead.

## 1. Create Or Select The External Tenant

Create the external tenant manually in the Microsoft Entra admin center: **Entra ID -> Overview -> Manage tenants -> Create -> External**. Select the immutable geography and link the tenant to an Azure subscription and billing resource group. The bootstrap scripts configure an existing external tenant; they do not create one.

Switch to the customer/external tenant that will host the Shopping users before recording values or managing the flow.

Record:

- Tenant name
- Tenant ID
- Primary domain, for example `<tenant-name>.onmicrosoft.com`
- CIAM authority host, for example `https://<tenant-name>.ciamlogin.com/`

## 2. Inspect `Shopping.Api`

The ExternalId bootstrap stage creates an app registration named `<workload>-<instance>-api`. Inspect it and record:

Record:

- Application client ID
- Tenant ID

In **Expose an API**, verify:

- Set Application ID URI to `api://<shopping-api-client-id>`
- Add delegated scope `access_as_user`
- Enable the scope

Suggested consent text:

- Admin consent display name: `Access Shopping API as the signed-in user`
- Admin consent description: `Allows the application to access the Shopping API on behalf of the signed-in user.`
- User consent display name: `Access Shopping API`
- User consent description: `Allows the application to access the Shopping API on your behalf.`

## 3. Inspect App Roles

The bootstrap defines these roles on both `<workload>-<instance>-web` and `<workload>-<instance>-api` so the Web ID token and API access token can carry the required role claims:

| Role | Allowed member types | Purpose |
| --- | --- | --- |
| `Admin` | Users/Groups | User administration and full privileged access |
| `Customer` | Users/Groups | Customer cart and account flows |
| `CatalogManager` | Users/Groups | Product, pricing, availability, and image management |

The role values must exactly match the constants in `ShoppingRoles.cs`.

## 4. Inspect `Shopping.Web`

The ExternalId bootstrap stage creates an app registration named `<workload>-<instance>-web`.

Verify the **Web** platform contains the configured local callbacks and every deployed Container Apps callback reconciled through bootstrap, including:

```text
https://localhost:7262/signin-oidc
https://<shopping-web-container-app-fqdn>/signin-oidc
```

For an Application Gateway or custom domain, set `ExternalId.PublicWebBaseUrls.<environment>` to the HTTPS origin, for example:

```text
https://shop.example.co.uk
```

Bootstrap adds `/signin-oidc` and replaces the authoritative redirect list. Do not edit it directly in the portal.

Use `-RotateWebClientSecret` to issue a credential and `-ConfigureLocalUserSecrets` to place it in the standard local .NET user-secrets store.

## 5. Inspect API Permission And Consent

On `<workload>-<instance>-web`, verify:

- Go to **API permissions**
- `<workload>-<instance>-api` is listed under **My APIs**
- Delegated permission `access_as_user` is present
- Tenant-wide consent is granted when required by policy

The scope value used by the app is:

```text
api://<shopping-api-client-id>/access_as_user
```

## 6. Create A Customer User Flow

Create a sign-up/sign-in user flow for customers.

Recommended initial choices:

- Allow email sign-up/sign-in
- Keep collected attributes minimal
- Add `Shopping.Web` to the user flow

Do not allow customers to choose privileged roles during sign-up.

Open the created flow, select **Applications**, and add the bootstrap-managed Web application. Use **Run user flow** to confirm the sign-up link and intended providers are visible. If the link is absent, verify that this is a combined sign-up/sign-in flow rather than sign-in-only.

The workforce/B2B Microsoft provider is not automatically a customer identity provider for personal Outlook accounts. Use local customer identities or configure a supported customer provider/custom federation deliberately.

## 7. Bootstrap The First Admin

The external-tenant administrator is not automatically a Shopping customer. A B2B administrator and a customer using the same email address are separate directory objects.

Create the first trusted customer in the external tenant:

1. Go to **Entra ID -> Users -> New user -> Create new external user**.
2. Under **Identities**, select **Email** and enter the customer sign-in address.
3. Enter the display name and copy the generated temporary password directly to the intended operator.
4. Require password change on first sign-in and create the customer.
5. Copy the customer object's Object ID to `ExternalId.BootstrapAdminUserObjectId` in the ignored bootstrap configuration.
6. Rerun `Initialize-ShoppingBootstrap.ps1 -Stage ExternalId` to assign `Admin` to both Web and API.

Do not place the temporary password in bootstrap configuration or state. After this, future privileged role management can be handled through the app when Microsoft Graph-backed admin features are implemented.

Privileged roles:

- `Admin`
- `CatalogManager`

These must be assigned explicitly. They must not be self-service.

The current `CustomerAccess` policy also requires `Customer` or `Admin`. Entra self-service sign-up does not automatically assign `Customer`, so new accounts need a manual role assignment until an approved application provisioning or baseline authorization change is implemented.

## 8. Configure Local User Secrets

Run these from the repository root.

```powershell
dotnet user-secrets set "EntraExternalId:Instance" "https://<tenant-name>.ciamlogin.com/" --project .\src\Shopping.Web
dotnet user-secrets set "EntraExternalId:Domain" "<tenant-name>.onmicrosoft.com" --project .\src\Shopping.Web
dotnet user-secrets set "EntraExternalId:TenantId" "<tenant-id>" --project .\src\Shopping.Web
dotnet user-secrets set "EntraExternalId:ClientId" "<web-app-client-id>" --project .\src\Shopping.Web
dotnet user-secrets set "EntraExternalId:ClientSecret" "<web-app-client-secret>" --project .\src\Shopping.Web
dotnet user-secrets set "ShoppingApi:Scopes:0" "api://<api-app-client-id>/access_as_user" --project .\src\Shopping.Web

dotnet user-secrets set "EntraExternalId:Instance" "https://<tenant-name>.ciamlogin.com/" --project .\src\Shopping.Api
dotnet user-secrets set "EntraExternalId:TenantId" "<tenant-id>" --project .\src\Shopping.Api
dotnet user-secrets set "EntraExternalId:ClientId" "<api-app-client-id>" --project .\src\Shopping.Api
dotnet user-secrets set "EntraExternalId:Audience" "api://<api-app-client-id>" --project .\src\Shopping.Api
```

## 9. Verify Locally

Start the local Docker dependencies first, including Redis.

Run the API:

```powershell
dotnet run --project .\src\Shopping.Api\Shopping.Api.csproj --launch-profile https
```

Run the Blazor app:

```powershell
dotnet run --project .\src\Shopping.Web\Shopping.Web.csproj --launch-profile https
```

Open:

```text
https://localhost:7262
```

Protected pages should redirect to the Entra External ID sign-in experience.

## References

- [Create a sign-up and sign-in user flow](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-user-flow-sign-up-sign-in-customers)
- [Add an application to a user flow](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-user-flow-add-application)
- [Use app roles in Microsoft Entra External ID](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-use-app-roles-customers)
- [Expose a web API](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-expose-web-apis)
- [Configure client access to a web API](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-access-web-apis)
- [Scopes and permissions](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc)
