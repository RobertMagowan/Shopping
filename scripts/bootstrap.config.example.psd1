@{
    Repository = "<github-owner>/<github-repository>"
    Branch = "master"
    WorkloadName = "shopping"
    # Optional. Defaults to a safe slug derived from the canonical GitHub owner/repository.
    # Set explicitly when a different stable installation label is required.
    InstanceName = ""
    Environments = @("dev", "test", "prod")

    Azure = @{
        TenantId = "<azure-resource-tenant-id>"
        SubscriptionId = "<azure-subscription-id>"
        Location = "uksouth"
        # Keep Redis with the application unless Azure reports regional capacity constraints.
        ManagedRedisLocations = @{
            dev = "uksouth"
            test = "uksouth"
            prod = "uksouth"
        }
        # Enable production zone redundancy when the subscription, region, and SQL SKU accept it.
        SqlZoneRedundancy = @{
            dev = $false
            test = $false
            prod = $true
        }
        DeploymentRoles = @(
            "Contributor"
            "Role Based Access Control Administrator"
        )
    }

    ExternalId = @{
        # Copy this from the External ID tenant overview, not the Azure subscription's home tenant.
        TenantId = "<external-id-tenant-id>"
        Domain = "<tenant-name>.onmicrosoft.com"
        Instance = "https://<tenant-name>.ciamlogin.com/"
        WebRedirectUris = @(
            "https://localhost:7262/signin-oidc"
            "http://localhost:5140/signin-oidc"
        )
        # Set each value after the first Container Apps deployment reports its
        # Web origin, or set a known custom-domain origin before deployment.
        PublicWebBaseUrls = @{
            dev = ""
            test = ""
            prod = ""
        }
        # Use -PromptForExternalIdValues to enter this email interactively. Bootstrap
        # creates a missing local account and displays its temporary password once.
        BootstrapAdminEmail = ""
        # Compatibility override for installations that already record a user object ID.
        BootstrapAdminUserObjectId = ""
    }

    GitHub = @{
        ProductionReviewers = @("<github-user>")
        RulesetName = "protected master"
    }

    SqlAdministratorLogin = "sqladminuser"
}
