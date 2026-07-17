# Repository Guidelines

## Agent Operating Rules

- Treat these instructions as directive, not advisory.
- Do not alter Microsoft Entra resources, app registrations, user flows, scopes, roles, or assignments unless the user explicitly asks for that operation.
- Browser-to-API traffic must follow the BFF pattern: the browser talks to `Shopping.Web`; `Shopping.Web` calls `Shopping.Api` through the declarative Microsoft.Identity.Web downstream API registration.
- Do not add direct browser calls from Blazor components to `Shopping.Api`.
- Do not add fake, bypass, or development-only authentication schemes. All environments use Microsoft Entra External ID.
- Do not replace Redis-backed distributed token caching with in-memory token caches.

## Project Structure & Module Organization

This repository contains a .NET 10 shopping application.

- `Shopping.slnx` is the solution entry point.
- `src/Shopping.Web` contains the Blazor Web App UI and page components.
- `src/Shopping.Api` contains the ASP.NET Core REST API, controllers, auth policies, and health endpoint.
- `src/Shopping.Application` contains use-case services and DTOs.
- `src/Shopping.Domain` contains core domain models, roles, and policy constants.
- `src/Shopping.Infrastructure` contains SQL Server/Azure SQL, Blob Storage, Redis, and Service Bus integrations.
- `tests/Shopping.Application.Tests` and `tests/Shopping.Api.Tests` contain xUnit tests.

Public assets for the Blazor app live under `src/Shopping.Web/wwwroot`.

## Architecture Boundaries

- `Shopping.Web` owns Blazor UI, browser sign-in, cookie sessions, server-side token acquisition, and BFF calls to the API.
- `Shopping.Api` owns REST endpoints, JWT bearer validation, authorization policies, and API contracts.
- `Shopping.Application` owns use cases, DTOs, validation, and business workflows.
- `Shopping.Domain` owns core models, invariants, roles, and policy constants.
- `Shopping.Infrastructure` owns Azure SDK clients, emulator integrations, persistence, cache, storage, messaging, and Microsoft Graph integrations.

Keep business logic out of Razor components and controllers. Keep Azure/client construction out of `Web`, `Api`, `Application`, and `Domain` unless there is a specific framework boundary reason.

## Build, Test, and Development Commands

Run commands from `C:\repos\Shopping`.

```powershell
dotnet restore Shopping.slnx
dotnet build Shopping.slnx
dotnet test Shopping.slnx
dotnet tool restore
```

Run the API locally:

```powershell
dotnet run --project .\src\Shopping.Api\Shopping.Api.csproj --launch-profile https
```

Run the Blazor app locally:

```powershell
dotnet run --project .\src\Shopping.Web\Shopping.Web.csproj --launch-profile https
```

Development configuration expects SQL Server, Azurite, Redis, and Service Bus emulator to be available through Docker. Local Docker SQL Server may use SQL authentication in user secrets. Non-development Azure SQL connections must use Microsoft Entra authentication through managed identity. `Shopping.Web` requires Redis for Microsoft.Identity.Web distributed token caching; local development uses `ShoppingAzure:Redis:ConnectionString=localhost:6379`.

Required local service ports:

- Azurite: `10000`, `10001`, `10002`
- SQL Server: `1433`
- Redis: `6379`
- Service Bus emulator: `5672`, `5300`

## Local Process Cleanup

Before ending a prompt or handing control back to a developer, stop any running processes for this solution. Do not leave `dotnet run`, API, or Blazor dev-server processes running because they can lock build outputs in Visual Studio.

Use this cleanup command when needed:

```powershell
$procs = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -in @('dotnet.exe','iisexpress.exe','Shopping.Api.exe','Shopping.Web.exe') -and
  ($_.CommandLine -like '*C:\repos\Shopping*' -or
   $_.CommandLine -like '*Shopping.Api*' -or
   $_.CommandLine -like '*Shopping.Web*')
}
$procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

If local ports were used, also verify that `7202`, `7262`, `5044`, and `5140` are free before opening the solution in Visual Studio.

## Coding Style & Naming Conventions

Use standard C# conventions: four-space indentation, nullable reference types enabled, PascalCase for public types and members, camelCase for locals and private fields. Keep controllers thin and move business logic into `Shopping.Application`. Keep Azure/client setup in `Shopping.Infrastructure`.

Prefer explicit DTOs for API contracts. Do not expose persistence models directly through controllers or Blazor pages.

Application-layer code must match the existing `src/Shopping.Application` style:

- Put the file-scoped namespace first, then namespace-local `using` directives.
- Use `sealed` classes for handlers and `record` types for command/query messages.
- Put each command/query message and its handler in the same file, with the message record first and the handler immediately after it.
- Use explicit handler interfaces such as `IGetPublishedProductsQueryHandler`.
- Name CQRS methods `HandleAsync(...)`; name async port methods with the `Async` suffix.
- Prefer primary constructors for simple dependency injection.
- Wrap long constructor and method parameter lists onto aligned continuation lines.
- Format fluent LINQ chains one call per line when they span multiple operations.
- Keep ports in `Shopping.Application`; keep EF Core, Azure SDKs, SQL, Blob Storage, and emulator code out of this project.

Example:

```csharp
namespace Shopping.Application.Catalog;

using Contracts.Catalog;

public sealed class ExampleQueryHandler(IExampleRepository repository) : IExampleQueryHandler
{
    public async Task<IReadOnlyCollection<ProductDto>> HandleAsync(ExampleQuery query,
                                                                   CancellationToken cancellationToken)
    {
        var products = await repository.GetProductsAsync(cancellationToken);

        return products.OrderBy(product => product.Name)
                       .Select(ToDto)
                       .ToArray();
    }
}
```

## Testing Guidelines

Tests use xUnit. Name test classes after the unit or endpoint under test, for example `ProductCatalogTests` or `ProductsControllerTests`. Use clear test method names that describe behavior, such as `GetProducts_ReturnsPublishedProducts`.

Run all tests with:

```powershell
dotnet test Shopping.slnx
```

Add unit tests for application/domain logic and integration tests for API routing, auth behavior, and dependency wiring.

Before reporting completion, run:

```powershell
dotnet build Shopping.slnx
```

Also run `dotnet test Shopping.slnx` when changing auth, API behavior, domain/application logic, configuration binding, or infrastructure registration.

## Commit & Pull Request Guidelines

This repository has no git history yet. Use Conventional Commits going forward:

```text
feat(api): add product catalog endpoint
fix(blazor): correct cart authorization policy
chore(config): add local emulator settings
```

Pull requests should include a concise summary, testing evidence, configuration changes, and any Azure or emulator impacts. Include screenshots for visible Blazor UI changes.

## Security & Configuration Tips

All environments use Microsoft Entra External ID for authentication. `Shopping.Web` must use distributed token caching backed by Redis, not in-memory token caches. Do not commit secrets, connection strings with credentials, or keys. `appsettings.Development.json` is local-only. Azure-hosted `dev`, `test`, and `prod` settings must be supplied by App Service configuration created by IaC. Sensitive deployed values must be stored in Key Vault and exposed to App Service with Key Vault references.

Treat `scripts/bootstrap.config.psd1` and `scripts/bootstrap-state.local.json` as local bootstrap inputs and state; neither may contain secrets or be committed. Use `Initialize-ShoppingBootstrap.ps1` as the bootstrap entry point and run `Test-ShoppingBootstrap.ps1` after changes. The bootstrap scripts authoritatively own the dedicated Shopping app roles, scope, permissions, redirect URIs, GitHub environments, OIDC credentials, and named ruleset. Preview bootstrap changes with `-WhatIf`; do not make competing manual edits to script-owned properties.

Use `-PromptForExternalIdValues` only for operator-driven bootstrap runs. CI and other unattended execution must provide configuration explicitly and must not enable interactive prompts.

Do not independently change the App Service resource suffix algorithm in PowerShell, GitHub configuration, or Bicep. Bootstrap-generated `RESOURCE_SUFFIX` values make deployed hostnames and Entra redirect URIs deterministic before first deployment; update and verify all three locations together.

Treat the resolved deployment instance as immutable after infrastructure is created. Each repository installation needs a distinct `InstanceName` within a shared Azure subscription; changing it changes resource-group and global resource identities.
