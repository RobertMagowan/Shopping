namespace Shopping.Infrastructure.Persistence.Entities;

public sealed class ProductEntity
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

    public ICollection<ProductImageEntity> Images { get; init; } = [];
}
