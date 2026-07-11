using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Shopping.Infrastructure.Storage;

public sealed class ProductImageBlobSeedHostedService(
    BlobContainerClient containerClient,
    ProductImageStorageOptions options,
    ILogger<ProductImageBlobSeedHostedService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (!options.SeedOnStartup)
        {
            return;
        }

        await containerClient.CreateIfNotExistsAsync(
            PublicAccessType.Blob,
            cancellationToken: cancellationToken);
        await containerClient.SetAccessPolicyAsync(
            PublicAccessType.Blob,
            cancellationToken: cancellationToken);

        foreach (var seed in ProductImageBlobSeedData.Items)
        {
            var blobClient = containerClient.GetBlobClient(seed.BlobName);
            var svg = ProductImageBlobSeedData.CreateSvg(seed);

            using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(svg));
            await blobClient.UploadAsync(stream, overwrite: true, cancellationToken);
            await blobClient.SetHttpHeadersAsync(
                new BlobHttpHeaders
                {
                    ContentType = "image/svg+xml; charset=utf-8"
                },
                cancellationToken: cancellationToken);
        }

        logger.LogInformation(
            "Seeded {ImageCount} product image blobs into container {ContainerName}.",
            ProductImageBlobSeedData.Items.Length,
            options.ContainerName);
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}
