using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Shopping.Application.Catalog;
using Shopping.Infrastructure.Catalog;
using Shopping.Infrastructure.Configuration;
using Shopping.Infrastructure.Persistence;
using StackExchange.Redis;

namespace Shopping.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddShoppingInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        IHostEnvironment environment)
    {
        var section = configuration.GetSection(ShoppingAzureOptions.SectionName);
        services.Configure<ShoppingAzureOptions>(section);

        var options = section.Get<ShoppingAzureOptions>() ?? new ShoppingAzureOptions();
        var databaseConnectionString = configuration.GetConnectionString("ShoppingDatabase");

        if (!string.IsNullOrWhiteSpace(options.Storage.ConnectionString))
        {
            services.AddSingleton(new BlobServiceClient(options.Storage.ConnectionString));
        }

        if (!string.IsNullOrWhiteSpace(databaseConnectionString))
        {
            ValidateDatabaseAuthentication(databaseConnectionString, environment);
            services.AddDbContext<ShoppingDbContext>(dbContextOptions =>
                dbContextOptions.UseSqlServer(databaseConnectionString, sqlServerOptions =>
                    sqlServerOptions.EnableRetryOnFailure()));
            services.AddScoped<IProductCatalog, SqlProductCatalog>();
        }

        if (!string.IsNullOrWhiteSpace(options.Redis.ConnectionString))
        {
            services.AddSingleton<IConnectionMultiplexer>(_ =>
                ConnectionMultiplexer.Connect(options.Redis.ConnectionString));
        }

        if (!string.IsNullOrWhiteSpace(options.ServiceBus.ConnectionString))
        {
            services.AddSingleton(new ServiceBusClient(options.ServiceBus.ConnectionString));
        }

        return services;
    }

    private static void ValidateDatabaseAuthentication(
        string connectionString,
        IHostEnvironment environment)
    {
        if (environment.IsDevelopment())
        {
            return;
        }

        var builder = new SqlConnectionStringBuilder(connectionString);
        var authentication = builder.Authentication.ToString();

        var usesManagedIdentity =
            string.Equals(authentication, "ActiveDirectoryManagedIdentity", StringComparison.Ordinal) ||
            string.Equals(authentication, "ActiveDirectoryMSI", StringComparison.Ordinal) ||
            string.Equals(authentication, "ActiveDirectoryDefault", StringComparison.Ordinal) ||
            string.Equals(authentication, "ActiveDirectoryWorkloadIdentity", StringComparison.Ordinal);

        if (!usesManagedIdentity || !string.IsNullOrWhiteSpace(builder.Password))
        {
            throw new InvalidOperationException(
                "Non-development database connections must use Microsoft Entra authentication. " +
                "Use an Azure SQL connection string with 'Authentication=Active Directory Managed Identity' " +
                "or another managed identity compatible Microsoft Entra authentication mode.");
        }
    }
}
