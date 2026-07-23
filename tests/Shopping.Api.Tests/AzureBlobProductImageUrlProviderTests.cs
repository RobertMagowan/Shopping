namespace Shopping.Api.Tests;

using Shopping.Infrastructure.Storage;

public sealed class AzureBlobProductImageUrlProviderTests
{
    [Fact]
    public void SharedAccessSignatureExpiryPreservesConfiguredLifetime()
    {
        var options = new ProductImageStorageOptions
        {
            SharedAccessSignatureLifetimeMinutes = 10
        };
        var provider = new AzureBlobProductImageUrlProvider(null!,
                                                            null!,
                                                            options);
        var utcNow = new DateTimeOffset(2026, 7, 23, 5, 49, 56, TimeSpan.Zero);

        var signatureWindow = provider.GetSharedAccessSignatureWindow(utcNow);

        Assert.True(signatureWindow.ExpiresOn >= utcNow.AddMinutes(10),
                    $"The SAS expires after {signatureWindow.ExpiresOn - utcNow}, less than the configured lifetime.");
    }

    [Fact]
    public void SharedAccessSignatureWindowIsStableWithinConfiguredLifetime()
    {
        var options = new ProductImageStorageOptions
        {
            SharedAccessSignatureLifetimeMinutes = 10
        };
        var provider = new AzureBlobProductImageUrlProvider(null!,
                                                            null!,
                                                            options);
        var windowStart = new DateTimeOffset(2026, 7, 23, 5, 40, 1, TimeSpan.Zero);
        var windowEnd = new DateTimeOffset(2026, 7, 23, 5, 49, 59, TimeSpan.Zero);

        var firstWindow = provider.GetSharedAccessSignatureWindow(windowStart);
        var secondWindow = provider.GetSharedAccessSignatureWindow(windowEnd);

        Assert.Equal(firstWindow, secondWindow);
    }

    [Fact]
    public void SharedAccessSignatureWindowChangesAtConfiguredBoundary()
    {
        var options = new ProductImageStorageOptions
        {
            SharedAccessSignatureLifetimeMinutes = 10
        };
        var provider = new AzureBlobProductImageUrlProvider(null!,
                                                            null!,
                                                            options);
        var previousWindowEnd = new DateTimeOffset(2026, 7, 23, 5, 49, 59, TimeSpan.Zero);
        var nextWindowStart = new DateTimeOffset(2026, 7, 23, 5, 50, 0, TimeSpan.Zero);

        var previousWindow = provider.GetSharedAccessSignatureWindow(previousWindowEnd);
        var nextWindow = provider.GetSharedAccessSignatureWindow(nextWindowStart);

        Assert.NotEqual(previousWindow, nextWindow);
    }

    [Fact]
    public void DelegationKeyCannotBeReusedWhenItStartsAfterRequestedWindow()
    {
        var cachedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 45, 0, TimeSpan.Zero);
        var cachedExpiresOn = new DateTimeOffset(2026, 7, 23, 6, 10, 0, TimeSpan.Zero);
        var requestedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 35, 0, TimeSpan.Zero);
        var requestedExpiresOn = new DateTimeOffset(2026, 7, 23, 6, 0, 0, TimeSpan.Zero);

        var canReuse = AzureBlobProductImageUrlProvider.CanReuseUserDelegationKey(cachedStartsOn,
                                                                                  cachedExpiresOn,
                                                                                  requestedStartsOn,
                                                                                  requestedExpiresOn);

        Assert.False(canReuse);
    }

    [Fact]
    public void DelegationKeyCanBeReusedWhenItCoversRequestedWindow()
    {
        var cachedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 35, 0, TimeSpan.Zero);
        var cachedExpiresOn = new DateTimeOffset(2026, 7, 23, 6, 10, 0, TimeSpan.Zero);
        var requestedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 45, 0, TimeSpan.Zero);
        var requestedExpiresOn = new DateTimeOffset(2026, 7, 23, 6, 0, 0, TimeSpan.Zero);

        var canReuse = AzureBlobProductImageUrlProvider.CanReuseUserDelegationKey(cachedStartsOn,
                                                                                  cachedExpiresOn,
                                                                                  requestedStartsOn,
                                                                                  requestedExpiresOn);

        Assert.True(canReuse);
    }

    [Fact]
    public void DelegationKeyCannotBeReusedWhenItExpiresBeforeRequestedWindow()
    {
        var cachedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 35, 0, TimeSpan.Zero);
        var cachedExpiresOn = new DateTimeOffset(2026, 7, 23, 5, 55, 0, TimeSpan.Zero);
        var requestedStartsOn = new DateTimeOffset(2026, 7, 23, 5, 45, 0, TimeSpan.Zero);
        var requestedExpiresOn = new DateTimeOffset(2026, 7, 23, 6, 0, 0, TimeSpan.Zero);

        var canReuse = AzureBlobProductImageUrlProvider.CanReuseUserDelegationKey(cachedStartsOn,
                                                                                  cachedExpiresOn,
                                                                                  requestedStartsOn,
                                                                                  requestedExpiresOn);

        Assert.False(canReuse);
    }
}
