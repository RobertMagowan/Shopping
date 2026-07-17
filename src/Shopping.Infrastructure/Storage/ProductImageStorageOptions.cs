namespace Shopping.Infrastructure.Storage;

public sealed class ProductImageStorageOptions
{
    public const string SectionName = "ProductImageStorage";

    public string ConnectionString { get; init; } = "";

    public string ServiceUri { get; init; } = "";

    public string ContainerName { get; init; } = "product-images";

    public string PublicBaseUri { get; init; } = "";

    public bool UseSharedAccessSignatures { get; init; }

    public int SharedAccessSignatureLifetimeMinutes { get; init; } = 10;

    public bool SeedOnStartup { get; init; } = true;
}
