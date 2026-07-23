namespace Shopping.Infrastructure.Storage;

using Application.Catalog;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

public sealed class AzureBlobProductImageUrlProvider(
    BlobServiceClient serviceClient,
    BlobContainerClient containerClient,
    ProductImageStorageOptions options) : IProductImageUrlProvider
{
    private readonly SemaphoreSlim userDelegationKeyLock = new(1, 1);
    private UserDelegationKeyCacheEntry? cachedUserDelegationKey;

    public async Task<string?> GetImageUrlAsync(string? blobName,
                                                CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(blobName))
        {
            return null;
        }

        var imageUri = GetBaseImageUri(blobName);

        if (!options.UseSharedAccessSignatures)
        {
            return imageUri;
        }

        var signatureWindow = GetSharedAccessSignatureWindow(DateTimeOffset.UtcNow);
        var userDelegationKey = await GetUserDelegationKeyAsync(signatureWindow.StartsOn,
                                                                signatureWindow.ExpiresOn,
                                                                cancellationToken);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = options.ContainerName,
            BlobName = blobName,
            Resource = "b",
            StartsOn = signatureWindow.StartsOn,
            ExpiresOn = signatureWindow.ExpiresOn,
            Protocol = SasProtocol.Https
        };

        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        var sasQuery = sasBuilder.ToSasQueryParameters(userDelegationKey,
                                                       serviceClient.AccountName);

        return $"{imageUri}?{sasQuery}";
    }

    private async Task<UserDelegationKey> GetUserDelegationKeyAsync(DateTimeOffset startsOn,
                                                                    DateTimeOffset expiresOn,
                                                                    CancellationToken cancellationToken)
    {
        var cacheEntry = Volatile.Read(ref cachedUserDelegationKey);

        if (CanReuseCachedUserDelegationKey(cacheEntry, startsOn, expiresOn))
        {
            return cacheEntry!.Key;
        }

        await userDelegationKeyLock.WaitAsync(cancellationToken);

        try
        {
            cacheEntry = Volatile.Read(ref cachedUserDelegationKey);

            if (CanReuseCachedUserDelegationKey(cacheEntry, startsOn, expiresOn))
            {
                return cacheEntry!.Key;
            }

            var userDelegationKey = await serviceClient.GetUserDelegationKeyAsync(startsOn,
                                                                                  expiresOn,
                                                                                  cancellationToken);

            cacheEntry = new UserDelegationKeyCacheEntry(userDelegationKey.Value,
                                                         startsOn,
                                                         expiresOn);
            Volatile.Write(ref cachedUserDelegationKey, cacheEntry);

            return cacheEntry.Key;
        }
        finally
        {
            userDelegationKeyLock.Release();
        }
    }

    private static bool CanReuseCachedUserDelegationKey(UserDelegationKeyCacheEntry? cacheEntry,
                                                        DateTimeOffset startsOn,
                                                        DateTimeOffset expiresOn)
    {
        return cacheEntry is not null &&
               CanReuseUserDelegationKey(cacheEntry.StartsOn,
                                         cacheEntry.ExpiresOn,
                                         startsOn,
                                         expiresOn);
    }

    internal static bool CanReuseUserDelegationKey(DateTimeOffset cachedStartsOn,
                                                    DateTimeOffset cachedExpiresOn,
                                                    DateTimeOffset requestedStartsOn,
                                                    DateTimeOffset requestedExpiresOn)
    {
        return cachedStartsOn <= requestedStartsOn &&
               cachedExpiresOn >= requestedExpiresOn;
    }

    private string GetBaseImageUri(string blobName)
    {
        if (!string.IsNullOrWhiteSpace(options.PublicBaseUri))
        {
            return $"{options.PublicBaseUri.TrimEnd('/')}/{blobName.TrimStart('/')}";
        }

        return containerClient.GetBlobClient(blobName).Uri.AbsoluteUri;
    }

    internal (DateTimeOffset StartsOn, DateTimeOffset ExpiresOn) GetSharedAccessSignatureWindow(DateTimeOffset utcNow)
    {
        var lifetimeMinutes = Math.Max(1, options.SharedAccessSignatureLifetimeMinutes);
        var lifetimeSeconds = lifetimeMinutes * 60L;
        var currentWindow = utcNow.ToUnixTimeSeconds() / lifetimeSeconds;
        var windowStartsOn = DateTimeOffset.FromUnixTimeSeconds(currentWindow * lifetimeSeconds);

        return (windowStartsOn.AddMinutes(-5),
                windowStartsOn.AddSeconds(lifetimeSeconds * 2));
    }

    private sealed record UserDelegationKeyCacheEntry(UserDelegationKey Key,
                                                      DateTimeOffset StartsOn,
                                                      DateTimeOffset ExpiresOn);
}
