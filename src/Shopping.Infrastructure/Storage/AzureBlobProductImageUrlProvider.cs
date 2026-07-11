using Azure.Storage.Blobs;
using Shopping.Application.Catalog;

namespace Shopping.Infrastructure.Storage;

public sealed class AzureBlobProductImageUrlProvider(
    BlobContainerClient containerClient,
    ProductImageStorageOptions options) : IProductImageUrlProvider
{
    public string? GetImageUrl(string? blobName)
    {
        if (string.IsNullOrWhiteSpace(blobName))
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(options.PublicBaseUri))
        {
            return $"{options.PublicBaseUri.TrimEnd('/')}/{blobName.TrimStart('/')}";
        }

        return containerClient.GetBlobClient(blobName).Uri.AbsoluteUri;
    }
}
