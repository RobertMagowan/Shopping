# Microsoft Entra External ID Manual Setup

Use this guide to configure Microsoft Entra External ID manually. Do not automate these steps until you intentionally choose to.

## 1. Create Or Select The External Tenant

Use the Microsoft Entra admin center and switch to the customer/external tenant that will host the shopping users.

Record:

- Tenant name
- Tenant ID
- Primary domain, for example `<tenant-name>.onmicrosoft.com`
- CIAM authority host, for example `https://<tenant-name>.ciamlogin.com/`

## 2. Register `Shopping.Api`

Create an app registration named `Shopping.Api`.

Record:

- Application client ID
- Tenant ID

In **Expose an API**:

- Set Application ID URI to `api://<shopping-api-client-id>`
- Add delegated scope `access_as_user`
- Enable the scope

Suggested consent text:

- Admin consent display name: `Access Shopping API as the signed-in user`
- Admin consent description: `Allows the application to access the Shopping API on behalf of the signed-in user.`
- User consent display name: `Access Shopping API`
- User consent description: `Allows the application to access the Shopping API on your behalf.`

## 3. Add App Roles

On the `Shopping.Api` app registration, create these app roles:

| Role | Allowed member types | Purpose |
| --- | --- | --- |
| `Admin` | Users/Groups | User administration and full privileged access |
| `Customer` | Users/Groups | Customer cart and account flows |
| `CatalogManager` | Users/Groups | Product, pricing, availability, and image management |

The role values must exactly match the constants in `ShoppingRoles.cs`.

## 4. Register `Shopping.Web`

Create an app registration named `Shopping.Web`.

Configure platform type **Web** with redirect URI:

```text
https://localhost:7262/signin-oidc
```

Add additional deployed redirect URIs later, for example:

```text
https://<production-host>/signin-oidc
```

Create a client secret for local development and store it only in user secrets.

## 5. Grant API Permission To The Web App

On `Shopping.Web`:

- Go to **API permissions**
- Add a permission
- Choose **My APIs**
- Select `Shopping.Api`
- Select delegated permission `access_as_user`
- Grant consent if required by your tenant policy

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

## 7. Bootstrap The First Admin

Manually assign the first trusted user to the `Admin` app role. After this, future privileged role management can be handled through the app when Microsoft Graph-backed admin features are implemented.

Privileged roles:

- `Admin`
- `CatalogManager`

These must be assigned explicitly. They must not be self-service.

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
