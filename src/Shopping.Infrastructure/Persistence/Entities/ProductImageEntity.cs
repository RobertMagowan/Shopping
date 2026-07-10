namespace Shopping.Infrastructure.Persistence.Entities;

public sealed class ProductImageEntity
{
    public string Id { get; init; } = "";

    public string ProductId { get; init; } = "";

    public string BlobName { get; init; } = "";

    public string AltText { get; init; } = "";

    public int DisplayOrder { get; init; }

    public bool IsPrimary { get; init; }

    public ProductEntity Product { get; init; } = null!;
}
