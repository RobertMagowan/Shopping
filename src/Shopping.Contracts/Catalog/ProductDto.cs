namespace Shopping.Contracts.Catalog;

public sealed record ProductDto(
    string Id,
    string Name,
    string Description,
    decimal Price,
    string Currency,
    bool IsAvailable,
    string? ImageUrl);
