namespace Shopping.Application.Catalog;

public sealed class InMemoryProductCatalog : IProductCatalog
{
    private static readonly ProductDto[] Products =
    [
        new(
            "starter-coffee",
            "Starter Coffee",
            "A sample product used while local emulator persistence is being wired.",
            8.99m,
            "GBP",
            true,
            null),
        new(
            "ceramic-mug",
            "Ceramic Mug",
            "A sample product for the first customer-facing product list.",
            12.50m,
            "GBP",
            true,
            null)
    ];

    public Task<IReadOnlyCollection<ProductDto>> GetPublishedProductsAsync(CancellationToken cancellationToken)
    {
        return Task.FromResult<IReadOnlyCollection<ProductDto>>(Products);
    }
}
