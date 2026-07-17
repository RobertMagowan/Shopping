namespace Shopping.Application.Tests;

using Catalog;
using Domain.Catalog;

public sealed class GetPublishedProductsQueryTests
{
    [Fact]
    public async Task HandleAsync_maps_domain_products_to_catalog_contracts()
    {
        var handler = new GetPublishedProductsQueryHandler(new StubProductReadRepository([
                                                                                             new Product
                                                                                             {
                                                                                                 Id = "starter-coffee",
                                                                                                 Slug = "starter-coffee",
                                                                                                 Name = "Starter Coffee",
                                                                                                 Description = "A balanced ground coffee.",
                                                                                                 PriceAmount = 8.99m,
                                                                                                 Currency = "GBP",
                                                                                                 IsAvailable = true,
                                                                                                 IsPublished = true,
                                                                                                 StockQuantity = 10,
                                                                                                 Images =
                                                                                                 [
                                                                                                     new ProductImage
                                                                                                     {
                                                                                                         Id = "secondary",
                                                                                                         BlobName =
                                                                                                             "products/starter-coffee-secondary.svg",
                                                                                                         AltText = "Secondary image",
                                                                                                         DisplayOrder = 0,
                                                                                                         IsPrimary = false
                                                                                                     },
                                                                                                     new ProductImage
                                                                                                     {
                                                                                                         Id = "primary",
                                                                                                         BlobName = "products/starter-coffee.svg",
                                                                                                         AltText = "Primary image",
                                                                                                         DisplayOrder = 1,
                                                                                                         IsPrimary = true
                                                                                                     }
                                                                                                 ]
                                                                                             }
                                                                                         ]),
                                                           new StubProductImageUrlProvider("https://storage.test/"));

        var products = await handler.HandleAsync(new GetPublishedProductsQuery(), CancellationToken.None);

        var product = Assert.Single(products);
        Assert.Equal("starter-coffee", product.Id);
        Assert.Equal("Starter Coffee", product.Name);
        Assert.Equal(8.99m, product.Price);
        Assert.Equal("GBP", product.Currency);
        Assert.True(product.IsAvailable);
        Assert.Equal("https://storage.test/products/starter-coffee.svg", product.ImageUrl);
        Assert.Collection(product.ImageUrls,
                          imageUrl => Assert.Equal("https://storage.test/products/starter-coffee.svg", imageUrl),
                          imageUrl => Assert.Equal("https://storage.test/products/starter-coffee-secondary.svg", imageUrl));
    }

    [Fact]
    public async Task HandleAsync_uses_domain_purchase_rule_for_availability()
    {
        var handler = new GetPublishedProductsQueryHandler(new StubProductReadRepository([
                                                                                             new Product
                                                                                             {
                                                                                                 Id = "out-of-stock",
                                                                                                 Slug = "out-of-stock",
                                                                                                 Name = "Out Of Stock",
                                                                                                 Description = "No stock remains.",
                                                                                                 PriceAmount = 1.00m,
                                                                                                 Currency = "GBP",
                                                                                                 IsAvailable = true,
                                                                                                 IsPublished = true,
                                                                                                 StockQuantity = 0
                                                                                             }
                                                                                         ]),
                                                           new StubProductImageUrlProvider("https://storage.test/"));

        var products = await handler.HandleAsync(new GetPublishedProductsQuery(), CancellationToken.None);

        var product = Assert.Single(products);
        Assert.False(product.IsAvailable);
    }

    private sealed class StubProductReadRepository(IReadOnlyCollection<Product> products) : IProductReadRepository
    {
        public Task<IReadOnlyCollection<Product>> GetPublishedProductsAsync(CancellationToken cancellationToken) { return Task.FromResult(products); }
    }

    private sealed class StubProductImageUrlProvider(string baseUri) : IProductImageUrlProvider
    {
        public Task<string?> GetImageUrlAsync(string? blobName,
                                              CancellationToken cancellationToken)
        {
            return Task.FromResult(string.IsNullOrWhiteSpace(blobName) ? null : $"{baseUri}{blobName}");
        }
    }
}
