using Microsoft.EntityFrameworkCore;
using Shopping.Application.Catalog;
using Shopping.Infrastructure.Persistence;

namespace Shopping.Infrastructure.Catalog;

public sealed class SqlProductCatalog(ShoppingDbContext dbContext) : IProductCatalog
{
    public async Task<IReadOnlyCollection<ProductDto>> GetPublishedProductsAsync(
        CancellationToken cancellationToken)
    {
        var products = await dbContext.Products
            .AsNoTracking()
            .Where(product => product.IsPublished)
            .Select(product => new ProductDto(
                product.Id,
                product.Name,
                product.Description,
                product.PriceAmount,
                product.Currency,
                product.IsAvailable && product.StockQuantity > 0,
                product.Images
                    .OrderByDescending(image => image.IsPrimary)
                    .ThenBy(image => image.DisplayOrder)
                    .Select(image => image.BlobName)
                    .FirstOrDefault()))
            .OrderBy(product => product.Name)
            .ToArrayAsync(cancellationToken);

        return products;
    }
}
