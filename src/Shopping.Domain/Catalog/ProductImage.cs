namespace Shopping.Domain.Catalog;

public sealed class ProductImage
{
    public string Id { get; init; } = "";

    public string BlobName { get; init; } = "";

    public string AltText { get; init; } = "";

    public int DisplayOrder { get; init; }

    public bool IsPrimary { get; init; }
}