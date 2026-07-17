# Shopping

UK-focused public shopping site built with Blazor Web App, ASP.NET Core REST APIs, and Microsoft Entra External ID.

## Local development services

The development configuration expects these Docker-hosted emulators:

| Service | Local endpoint | Used for |
| --- | --- | --- |
| SQL Server | `localhost,1433` | Catalog, cart, order, and admin persistence |
| Azurite | `UseDevelopmentStorage=true` | Product images in Blob Storage |
| Redis | `localhost:6379` | Cart/cache state |
| Service Bus emulator | `sb://localhost` | Cart/order integration events |

The emulator-only connection values live in `src/Shopping.Api/appsettings.Development.json` and `src/Shopping.Web/appsettings.Development.json`.
Production should use managed identity, Key Vault, and real Azure resource endpoints.
The deployed relational database target is Azure SQL.

`Shopping.Web` uses Redis as the distributed cache for Microsoft.Identity.Web token acquisition. Local development uses the Docker Redis endpoint `localhost:6379`; production should point the same `ShoppingAzure:Redis:ConnectionString` setting to Azure Cache for Redis or the chosen managed Redis service.

The SQL Server connection string is secret-bearing in local Docker setups because it normally includes credentials. Store it in `Shopping.Api` user secrets:

```powershell
dotnet user-secrets set "ConnectionStrings:ShoppingDatabase" "Server=localhost,1433;Database=ShoppingDev;User Id=sa;Password=<your-sa-password>;Encrypt=False;TrustServerCertificate=True;" --project .\src\Shopping.Api
```

For deployed Azure environments, use Azure SQL with Microsoft Entra authentication instead of SQL passwords. The application validates this at startup outside Development.

System-assigned managed identity example:

```text
Server=tcp:<sql-server>.database.windows.net,1433;Database=<database>;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;
```

User-assigned managed identity example:

```text
Server=tcp:<sql-server>.database.windows.net,1433;Database=<database>;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;User Id=<managed-identity-client-id>;
```

The Azure SQL server must have a Microsoft Entra administrator configured. The app's managed identity must then be created as a contained database user and granted the minimum required database roles, for example `db_datareader`, `db_datawriter`, and execute permissions as needed.

## Run locally

Run the API:

```powershell
dotnet run --project .\src\Shopping.Api\Shopping.Api.csproj --launch-profile https
```

Run the Blazor app:

```powershell
dotnet run --project .\src\Shopping.Web\Shopping.Web.csproj --launch-profile https
```

## Database migrations and seed data

Restore local tools before working with EF Core migrations:

```powershell
dotnet tool restore
```

Create a migration after changing the persistence model:

```powershell
dotnet tool run dotnet-ef migrations add <MigrationName> --project .\src\Shopping.Infrastructure\Shopping.Infrastructure.csproj --startup-project .\src\Shopping.Api\Shopping.Api.csproj --context ShoppingDbContext --output-dir Persistence\Migrations
```

Apply migrations to the local SQL Server database:

```powershell
dotnet tool run dotnet-ef database update --project .\src\Shopping.Infrastructure\Shopping.Infrastructure.csproj --startup-project .\src\Shopping.Api\Shopping.Api.csproj --context ShoppingDbContext
```

The initial migration seeds sample products, prices, availability, and product image blob names. Product image blobs are stored separately in the `product-images` container.

## Authentication setup

All environments, including local development, use Microsoft Entra External ID. Replace the placeholder `EntraExternalId` values with the tenant and application registrations you configure manually.

Follow the full manual setup guide in [docs/entra-external-id-setup.md](docs/entra-external-id-setup.md).

The non-secret Entra values for local development live in `appsettings.Development.json`. Use user secrets only for secret values:

```powershell
dotnet user-secrets set "EntraExternalId:ClientSecret" "<web-app-client-secret>" --project .\src\Shopping.Web
```

## Authorization model

Roles are defined and assigned in Microsoft Entra External ID. Policies are defined in the application and map those role claims to app permissions.

| Policy | Allowed roles | Used for |
| --- | --- | --- |
| `AdminAccess` | `Admin` | User administration |
| `CustomerAccess` | `Customer`, `Admin` | Customer cart and account flows |
| `CatalogManagement` | `CatalogManager`, `Admin` | Product, pricing, availability, and image management |

Product browsing is currently anonymous. Privileged roles must not be self-assigned; bootstrap the first `Admin` manually in Entra, then use admin workflows for later role management.

## BFF API calls

Browser code must not call `Shopping.Api` directly. Use server-side services in `Shopping.Web` to call the API.

`Shopping.Web` declares `ShoppingApi` as a Microsoft.Identity.Web downstream API:

```json
"ShoppingApi": {
  "BaseUrl": "https://localhost:7202/",
  "Scopes": [
    "api://<api-app-client-id>/access_as_user"
  ]
}
```

`ShoppingApiClient` calls the named downstream API through `IDownstreamApi`. Microsoft.Identity.Web gets an access token for `ShoppingApi:Scopes` and adds it to outgoing API requests:

```text
Authorization: Bearer <access-token-for-Shopping.Api>
```

The API scope must match the delegated scope you expose manually on the `Shopping.Api` app registration, typically `api://<api-app-client-id>/access_as_user`.

## Deployment bootstrap

For the step-by-step Azure, GitHub, and External ID setup, see the [Shopping Environment Bootstrap Playbook](docs/bootstrap.md).
