namespace Shopping.Domain.Catalog;

public sealed class Product
{
    public string Id { get; init; } = "";

    public string Slug { get; init; } = "";

    public string Name { get; init; } = "";

    public string Description { get; init; } = "";

    public decimal PriceAmount { get; init; }

    public string Currency { get; init; } = "GBP";

    public bool IsAvailable { get; init; }

    public int StockQuantity { get; init; }

    public bool IsPublished { get; init; }

    public DateTimeOffset CreatedUtc { get; init; }

    public DateTimeOffset UpdatedUtc { get; init; }

    public ICollection<ProductImage> Images { get; init; } = [];

    public bool CanBePurchased { get => IsPublished && IsAvailable && StockQuantity > 0; }

    public string? PrimaryImageBlobName
    {
        get =>
            Images
                .OrderByDescending(image => image.IsPrimary)
                .ThenBy(image => image.DisplayOrder)
                .Select(image => image.BlobName)
                .FirstOrDefault();
    }

    public IReadOnlyCollection<string> OrderedImageBlobNames =>
        Images
            .OrderByDescending(image => image.IsPrimary)
            .ThenBy(image => image.DisplayOrder)
            .Select(image => image.BlobName)
            .ToArray();
}
