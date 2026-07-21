namespace Shopping.Api.Tests;

using Azure.Storage.Blobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Shopping.Infrastructure;

public sealed class InfrastructureDependencyInjectionTests
{
    [Fact]
    public void AddShoppingInfrastructureCreatesBlobClientForServiceUri()
    {
        const string serviceUri = "https://shopping.blob.core.windows.net";
        var configuration = new ConfigurationBuilder()
                            .AddInMemoryCollection(new Dictionary<string, string?>
                            {
                                ["ProductImageStorage:ServiceUri"] = serviceUri,
                                ["ProductImageStorage:ContainerName"] = "product-images",
                                ["ProductImageStorage:SeedOnStartup"] = "false"
                            })
                            .Build();
        var services = new ServiceCollection();

        services.AddShoppingInfrastructure(configuration, false);

        using var serviceProvider = services.BuildServiceProvider();
        var blobServiceClient = serviceProvider.GetRequiredService<BlobServiceClient>();

        Assert.Equal(new Uri(serviceUri), blobServiceClient.Uri);
    }
}
