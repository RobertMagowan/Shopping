namespace Shopping.Infrastructure;

using Application.Catalog;
using Azure.Core;
using Azure.Storage.Blobs;
using Catalog;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Persistence;
using Storage;

public static class DependencyInjection
{
    public static IServiceCollection AddShoppingInfrastructure(this IServiceCollection services,
                                                               IConfiguration configuration,
                                                               bool isDevelopment)
    {
        var databaseConnectionString = configuration.GetConnectionString("ShoppingDatabase");
        var productImageStorageOptions = GetProductImageStorageOptions(configuration);

        ValidateProductImageStorageAuthentication(productImageStorageOptions, isDevelopment);
        services.AddSingleton(productImageStorageOptions);
        services.AddSingleton(_ => CreateBlobServiceClient(productImageStorageOptions));
        services.AddSingleton(services =>
            services.GetRequiredService<BlobServiceClient>().GetBlobContainerClient(productImageStorageOptions.ContainerName));
        services.AddSingleton<IProductImageUrlProvider, AzureBlobProductImageUrlProvider>();
        services.AddHostedService<ProductImageBlobSeedHostedService>();

        if (!string.IsNullOrWhiteSpace(databaseConnectionString))
        {
            ValidateDatabaseAuthentication(databaseConnectionString, isDevelopment);
            services.AddDbContext<ShoppingDbContext>(dbContextOptions =>
                                                         dbContextOptions.UseSqlServer(databaseConnectionString, sqlServerOptions =>
                                                                                           sqlServerOptions.EnableRetryOnFailure()));
            services.AddScoped<IProductReadRepository, SqlProductReadRepository>();
        }

        return services;
    }

    private static ProductImageStorageOptions GetProductImageStorageOptions(IConfiguration configuration)
    {
        var seedOnStartupValue = configuration[$"{ProductImageStorageOptions.SectionName}:SeedOnStartup"];

        return new ProductImageStorageOptions
        {
            ConnectionString = configuration[$"{ProductImageStorageOptions.SectionName}:ConnectionString"] ?? "",
            ServiceUri = configuration[$"{ProductImageStorageOptions.SectionName}:ServiceUri"] ?? "",
            ContainerName = configuration[$"{ProductImageStorageOptions.SectionName}:ContainerName"] ?? "product-images",
            PublicBaseUri = configuration[$"{ProductImageStorageOptions.SectionName}:PublicBaseUri"] ?? "",
            UseSharedAccessSignatures = bool.TryParse(configuration[$"{ProductImageStorageOptions.SectionName}:UseSharedAccessSignatures"], out var useSharedAccessSignatures) &&
                                        useSharedAccessSignatures,
            SharedAccessSignatureLifetimeMinutes = int.TryParse(configuration[$"{ProductImageStorageOptions.SectionName}:SharedAccessSignatureLifetimeMinutes"],
                                                                out var sharedAccessSignatureLifetimeMinutes)
                ? sharedAccessSignatureLifetimeMinutes
                : 10,
            SeedOnStartup = string.IsNullOrWhiteSpace(seedOnStartupValue) || bool.Parse(seedOnStartupValue)
        };
    }

    private static BlobServiceClient CreateBlobServiceClient(ProductImageStorageOptions options)
    {
        var clientOptions = new BlobClientOptions(BlobClientOptions.ServiceVersion.V2021_12_02);

        if (!string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            return new BlobServiceClient(options.ConnectionString, clientOptions);
        }

        if (!string.IsNullOrWhiteSpace(options.ServiceUri))
        {
            return new BlobServiceClient(new Uri(options.ServiceUri, UriKind.Absolute), CreateDefaultAzureCredential(), clientOptions);
        }

        throw new InvalidOperationException("Missing product image storage configuration. Configure either " +
                                            "'ProductImageStorage:ConnectionString' for local development or " +
                                            "'ProductImageStorage:ServiceUri' for Azure-hosted environments.");
    }

    private static TokenCredential CreateDefaultAzureCredential()
    {
        var credentialType = Type.GetType("Azure.Identity.DefaultAzureCredential, Azure.Identity",
                                          true);

        return (TokenCredential)Activator.CreateInstance(credentialType!)!;
    }

    private static void ValidateDatabaseAuthentication(string connectionString,
                                                       bool isDevelopment)
    {
        if (isDevelopment)
        {
            return;
        }

        var builder = new SqlConnectionStringBuilder(connectionString);
        var authentication = builder.Authentication.ToString();

        var usesManagedIdentity = string.Equals(authentication, "ActiveDirectoryManagedIdentity", StringComparison.Ordinal) ||
                                  string.Equals(authentication, "ActiveDirectoryMSI", StringComparison.Ordinal) ||
                                  string.Equals(authentication, "ActiveDirectoryDefault", StringComparison.Ordinal) ||
                                  string.Equals(authentication, "ActiveDirectoryWorkloadIdentity", StringComparison.Ordinal);

        if (!usesManagedIdentity || !string.IsNullOrWhiteSpace(builder.Password))
        {
            throw new InvalidOperationException("Non-development database connections must use Microsoft Entra authentication. " +
                                                "Use an Azure SQL connection string with 'Authentication=Active Directory Managed Identity' " +
                                                "or another managed identity compatible Microsoft Entra authentication mode.");
        }
    }

    private static void ValidateProductImageStorageAuthentication(ProductImageStorageOptions options,
                                                                  bool isDevelopment)
    {
        if (isDevelopment || string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            return;
        }

        throw new InvalidOperationException("Non-development product image storage must use Microsoft Entra authentication. " +
                                            "Configure 'ProductImageStorage:ServiceUri' and grant the app managed identity Blob Storage access.");
    }
}
