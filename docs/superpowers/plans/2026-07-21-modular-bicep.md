# Modular Bicep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic resource-group template with capability-based Bicep modules without changing deployed resources or workflow contracts.

**Architecture:** Keep `infra/main.bicep` as the subscription entry point and `infra/modules/environment.bicep` as the resource-group orchestrator. Extract cohesive Azure capabilities into local modules, pass only required values, return non-secret resource identifiers and endpoints, and let symbolic references create implicit deployment dependencies.

**Tech Stack:** Azure Bicep, Azure CLI, PowerShell 7, GitHub Actions, Azure Container Apps, Azure SQL, Azure Managed Redis, Blob Storage, Key Vault, ACR, Front Door, Private Link.

## Global Constraints

- Preserve all `infra/main.bicep` parameters and outputs.
- Preserve all environment parameter-file contracts and deterministic resource names.
- Preserve conditional private endpoints, Front Door, and two-phase Container Apps deployment.
- Never expose SQL passwords, Entra client secrets, Redis keys, or connection strings through ordinary outputs.
- Use explicit `dependsOn` only for role-assignment propagation before Container Apps deployment.
- Keep production Key Vault purge protection enabled while omitting `enablePurgeProtection` in dev and test.
- Keep Web ingress external, API ingress internal, and both health probes on `/healthz`.

---

### Task 1: Add The Modular Structure Regression Test

**Files:**
- Create: `infra/tests/Test-BicepModules.ps1`
- Modify: `.github/workflows/infra.yml`

**Interfaces:**
- Consumes: `infra/modules/environment.bicep` and the required module filenames.
- Produces: a zero-exit structural CI gate named `Test modular Bicep structure`.

- [ ] **Step 1: Write the failing structural test**

Create a PowerShell test that requires these files and module declarations:

```powershell
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$infraRoot = Split-Path -Parent $PSScriptRoot
$orchestratorPath = Join-Path $infraRoot 'modules/environment.bicep'
$orchestrator = Get-Content -LiteralPath $orchestratorPath -Raw
$requiredModules = @(
    'network'
    'container-platform'
)

foreach ($moduleName in $requiredModules) {
    $modulePath = Join-Path $infraRoot "modules/$moduleName.bicep"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required Bicep module is missing: $moduleName.bicep"
    }

    if ($orchestrator -notmatch "module\s+\w+\s+'$([regex]::Escape($moduleName)).bicep'") {
        throw "environment.bicep does not invoke $moduleName.bicep"
    }
}

Write-Host 'Bicep module structure is valid.'
```

- [ ] **Step 2: Run the test and verify the expected failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\tests\Test-BicepModules.ps1
```

Expected: non-zero exit stating that `network.bicep` is missing.

- [ ] **Step 3: Add the test to infrastructure static validation**

Insert before `Build Bicep` in `.github/workflows/infra.yml`:

```yaml
      - name: Test modular Bicep structure
        shell: pwsh
        run: ./infra/tests/Test-BicepModules.ps1
```

### Task 2: Extract Networking And Container Platform

**Files:**
- Create: `infra/modules/network.bicep`
- Create: `infra/modules/container-platform.bicep`
- Modify: `infra/modules/environment.bicep`

**Interfaces:**
- `network.bicep` produces `virtualNetworkId`, `virtualNetworkName`, `containerAppsInfrastructureSubnetId`, and `privateEndpointSubnetId`.
- `container-platform.bicep` consumes `containerAppsInfrastructureSubnetId` and produces `containerAppsEnvironmentId` and `applicationInsightsConnectionString`.

- [ ] **Step 1: Extract network resources without renaming them**

Move the NSG, optional NAT public IP, optional NAT Gateway, VNet, and subnet references into `network.bicep`. Keep these address ranges exactly:

```bicep
var subnetConfiguration = {
  appGateway: '10.40.0.0/24'
  apim: '10.40.1.0/24'
  containerApps: '10.40.2.0/24'
  privateEndpoints: '10.40.3.0/24'
}
```

Return resource-derived IDs rather than reconstructing them in the orchestrator.

- [ ] **Step 2: Extract observability and the managed environment**

Move Log Analytics, workspace-based Application Insights, and the Container Apps managed environment into `container-platform.bicep`. Keep Log Analytics key access inside this module:

```bicep
appLogsConfiguration: {
  destination: 'log-analytics'
  logAnalyticsConfiguration: {
    customerId: logAnalytics.properties.customerId
    sharedKey: logAnalytics.listKeys().primarySharedKey
  }
}
```

- [ ] **Step 3: Invoke both modules from the orchestrator**

Pass shared names, `environmentName`, `location`, `enablePrivateEndpoints`, and `tags`. Reference `network.outputs.containerAppsInfrastructureSubnetId` from the platform module to create the implicit dependency.

- [ ] **Step 4: Compile every environment**

```powershell
az bicep build --file .\infra\main.bicep
az bicep build-params --file .\infra\parameters\dev.bicepparam
az bicep build-params --file .\infra\parameters\test.bicepparam
az bicep build-params --file .\infra\parameters\prod.bicepparam
```

Expected: four zero exit codes and no Bicep errors.

- [ ] **Step 5: Run the structural test and commit the green change**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\tests\Test-BicepModules.ps1
```

Expected: `Bicep module structure is valid.`

```powershell
git add infra/tests/Test-BicepModules.ps1 .github/workflows/infra.yml infra/modules/network.bicep infra/modules/container-platform.bicep infra/modules/environment.bicep infra/main.json
git commit -m "refactor(infra): extract network and container platform modules"
```

### Task 3: Extract Identities, Registry, Key Vault, And Storage

**Files:**
- Create: `infra/modules/identities.bicep`
- Create: `infra/modules/container-registry.bicep`
- Create: `infra/modules/key-vault.bicep`
- Create: `infra/modules/storage.bicep`
- Modify: `infra/modules/environment.bicep`

**Interfaces:**
- Identities return each identity name, ID, client ID, and principal ID.
- Registry returns name, ID, and login server.
- Key Vault returns name, ID, and optional Web secret URI.
- Storage returns account name, ID, blob endpoint, and container name.

- [ ] **Step 1: Extend the structural test and verify it fails**

Add `identities`, `container-registry`, `key-vault`, and `storage` to `$requiredModules`, then run the structural test. Expected: failure stating that `identities.bicep` is missing.

- [ ] **Step 2: Extract user-assigned identities**

Keep names `id-{workload}-web-{environment}-{suffix}` and `id-{workload}-api-{environment}-{suffix}`. Return principal IDs for RBAC and client IDs for runtime configuration.

- [ ] **Step 3: Extract ACR**

Preserve SKU, disabled admin user and anonymous pull, environment-dependent public access, and production zone redundancy.

- [ ] **Step 4: Extract Key Vault and Web credential storage**

Keep `entraExternalIdWebClientSecret` decorated with `@secure()`. Use conditional property composition:

```bicep
var purgeProtectionProperties = environmentName == 'prod' ? {
  enablePurgeProtection: true
} : {}
```

Return the secret URI only; never return the secret value.

- [ ] **Step 5: Extract product-image storage**

Preserve disabled public blob access, disabled shared-key access, TLS 1.2, environment storage redundancy, the `product-images` private container, and the resource-derived Blob endpoint.

- [ ] **Step 6: Run the structural test, compile, and commit**

Run the structural test and all four Bicep build commands from Task 2, then:

```powershell
git add infra/tests/Test-BicepModules.ps1 infra/modules/identities.bicep infra/modules/container-registry.bicep infra/modules/key-vault.bicep infra/modules/storage.bicep infra/modules/environment.bicep infra/main.json
git commit -m "refactor(infra): extract identity and platform data modules"
```

### Task 4: Extract SQL, Redis, And Image Delivery

**Files:**
- Create: `infra/modules/sql.bicep`
- Create: `infra/modules/redis.bicep`
- Create: `infra/modules/image-delivery.bicep`
- Modify: `infra/modules/environment.bicep`

**Interfaces:**
- SQL returns server name, server ID, database name, and server FQDN.
- Redis consumes an existing Key Vault name and returns Redis name, ID, and connection-string secret URI.
- Image delivery consumes Storage ID/name/blob endpoint and returns `frontDoorImageEndpoint` and `productImagePublicBaseUri`.

- [ ] **Step 1: Extend the structural test and verify it fails**

Add `sql`, `redis`, and `image-delivery` to `$requiredModules`, then run the structural test. Expected: failure stating that `sql.bicep` is missing.

- [ ] **Step 2: Extract SQL**

Keep the SQL administrator password secure, preserve the `ActiveDirectory` administrator bound to `deploymentPrincipalObjectId`, and retain SKU and zone-redundancy behavior.

- [ ] **Step 3: Extract Redis and write its secret internally**

Declare the Key Vault as existing by name. Keep the Redis key and constructed connection string inside `redis.bicep`:

```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource redisConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'shopping-web-redis-connection-string'
  properties: {
    value: '${redis.properties.hostName}:10000,password=${redisDatabase.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}
```

- [ ] **Step 4: Extract optional Front Door image delivery**

Preserve Premium SKU, private-link Blob origin, `/product-images` origin path, HTTPS-only route, and `UseQueryString` caching. Return the direct Blob container URI when Front Door is disabled.

- [ ] **Step 5: Run the structural test, compile, and commit**

Run all four Bicep build commands, then:

```powershell
git add infra/tests/Test-BicepModules.ps1 infra/modules/sql.bicep infra/modules/redis.bicep infra/modules/image-delivery.bicep infra/modules/environment.bicep infra/main.json
git commit -m "refactor(infra): extract SQL Redis and image delivery modules"
```

### Task 5: Extract RBAC And Private Connectivity

**Files:**
- Create: `infra/modules/access-control.bicep`
- Create: `infra/modules/private-endpoints.bicep`
- Modify: `infra/modules/environment.bicep`

**Interfaces:**
- Access control consumes registry/storage/Key Vault names and deployment/Web/API principal IDs.
- Private endpoints consume VNet/subnet IDs plus Storage, SQL, Key Vault, Redis, and ACR resource IDs.

- [ ] **Step 1: Extend the structural test and verify it fails**

Add `access-control` and `private-endpoints` to `$requiredModules`, then run the structural test. Expected: failure stating that `access-control.bicep` is missing.

- [ ] **Step 2: Extract role assignments**

Preserve exact built-in role IDs:

```bicep
var roleDefinitionIds = {
  blobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  blobDelegator: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}
```

Retain deterministic `guid()` assignment names and `ServicePrincipal` principal types.

- [ ] **Step 3: Extract private DNS and endpoints**

Keep the five zones and matching endpoint group IDs: Blob `blob`, SQL `sqlServer`, Key Vault `vault`, Redis `redisEnterprise`, and ACR `registry`. Deploy the module only when `enablePrivateEndpoints` is true.

- [ ] **Step 4: Run the structural test, compile, and commit**

Run all four Bicep build commands, then:

```powershell
git add infra/tests/Test-BicepModules.ps1 infra/modules/access-control.bicep infra/modules/private-endpoints.bicep infra/modules/environment.bicep infra/main.json
git commit -m "refactor(infra): extract access and private connectivity modules"
```

### Task 6: Extract Container Apps And Finish The Orchestrator

**Files:**
- Create: `infra/modules/container-apps.bicep`
- Modify: `infra/modules/environment.bicep`
- Modify: `infra/main.json`

**Interfaces:**
- Container Apps consumes all non-secret endpoints, identity IDs, image configuration, secret URIs, and runtime settings.
- It returns Web/API names, Web FQDN, and Web redirect URI.
- The orchestrator returns the exact pre-refactor output names to `main.bicep`.

- [ ] **Step 1: Extend the structural test and verify it fails**

Add `container-apps` to `$requiredModules` and add this final orchestrator assertion:

```powershell
$resourceDeclarations = [regex]::Matches($orchestrator, '(?m)^resource\s+').Count
if ($resourceDeclarations -gt 0) {
    throw "environment.bicep must orchestrate modules only; found $resourceDeclarations resource declarations."
}
```

Run the structural test. Expected: failure stating that `container-apps.bicep` is missing.

- [ ] **Step 2: Extract API and Web Container Apps**

Preserve internal-only API ingress, external HTTPS Web ingress, sticky Web sessions, commit-SHA images, scaling, Key Vault secret references, all environment-variable names, and both `/healthz` probes.

- [ ] **Step 3: Preserve deployment ordering**

Invoke `container-apps.bicep` only when `containerImageTag != 'bootstrap'` and add:

```bicep
dependsOn: [
  accessControl
]
```

Do not add dependencies already implied by module outputs.

- [ ] **Step 4: Reduce `environment.bicep` to orchestration**

Remove every direct `resource` declaration. Keep shared naming/configuration variables, module calls, and outputs. Ensure its output names exactly match the current file.

- [ ] **Step 5: Verify the structural test changes from red to green**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\tests\Test-BicepModules.ps1
```

Expected: `Bicep module structure is valid.`

- [ ] **Step 6: Compile and commit**

Run all four Bicep build commands, then:

```powershell
git add infra/tests/Test-BicepModules.ps1 infra/modules/container-apps.bicep infra/modules/environment.bicep infra/main.json
git commit -m "refactor(infra): complete modular environment orchestration"
```

### Task 7: Run Repository Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run infrastructure checks**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\tests\Test-BicepModules.ps1
az bicep build --file .\infra\main.bicep
az bicep build-params --file .\infra\parameters\dev.bicepparam
az bicep build-params --file .\infra\parameters\test.bicepparam
az bicep build-params --file .\infra\parameters\prod.bicepparam
```

- [ ] **Step 2: Run application checks**

```powershell
dotnet restore Shopping.slnx
dotnet build Shopping.slnx --configuration Release --no-restore
dotnet test Shopping.slnx --configuration Release --no-build
```

- [ ] **Step 3: Verify no accidental contract changes**

```powershell
git diff --check
git status --short
rg -n '^param |^output ' infra/main.bicep
```

Expected: clean formatting, successful builds/tests, and the original `main.bicep` parameter/output names.
