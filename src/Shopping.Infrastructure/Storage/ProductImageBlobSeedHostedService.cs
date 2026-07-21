namespace Shopping.Infrastructure.Storage;

using System.Text;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

public sealed class ProductImageBlobSeedHostedService(BlobContainerClient containerClient,
                                                      ProductImageStorageOptions options,
                                                      ILogger<ProductImageBlobSeedHostedService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (!options.SeedOnStartup)
        {
            return;
        }

        var publicAccessType = options.UseSharedAccessSignatures
            ? PublicAccessType.None
            : PublicAccessType.Blob;

        await containerClient.CreateIfNotExistsAsync(publicAccessType,
                                                     cancellationToken: cancellationToken);
        await containerClient.SetAccessPolicyAsync(publicAccessType,
                                                   cancellationToken: cancellationToken);

        foreach (var seed in ProductImageBlobSeedData.Items)
        {
            var blobClient = containerClient.GetBlobClient(seed.BlobName);
            var svg = ProductImageBlobSeedData.CreateSvg(seed);

            using var stream = new MemoryStream(Encoding.UTF8.GetBytes(svg));
            await blobClient.UploadAsync(stream, true, cancellationToken);
            await blobClient.SetHttpHeadersAsync(new BlobHttpHeaders { ContentType = "image/svg+xml; charset=utf-8" },
                                                 cancellationToken: cancellationToken);
        }

        logger.LogInformation("Seeded {ImageCount} product image blobs into container {ContainerName}.",
                              ProductImageBlobSeedData.Items.Length,
                              options.ContainerName);
    }

    public Task StopAsync(CancellationToken cancellationToken) { return Task.CompletedTask; }
}
