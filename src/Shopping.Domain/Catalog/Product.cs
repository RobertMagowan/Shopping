namespace Shopping.Domain.Catalog;

public sealed record Product(
    string Id,
    string Name,
    string Description,
    decimal Price,
    string Currency,
    bool IsAvailable,
    string? ImageUrl);
