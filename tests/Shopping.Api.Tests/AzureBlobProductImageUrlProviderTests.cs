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
}
