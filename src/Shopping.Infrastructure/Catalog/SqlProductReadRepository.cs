using Microsoft.EntityFrameworkCore;
using Shopping.Application.Catalog;
using Shopping.Domain.Catalog;
using Shopping.Infrastructure.Persistence;

namespace Shopping.Infrastructure.Catalog;

public sealed class SqlProductReadRepository(ShoppingDbContext dbContext) : IProductReadRepository
{
    public async Task<IReadOnlyCollection<Product>> GetPublishedProductsAsync(
        CancellationToken cancellationToken)
    {
        var products = await dbContext.Products
            .AsNoTracking()
            .Include(product => product.Images)
            .Where(product => product.IsPublished)
            .ToArrayAsync(cancellationToken);

        return products;
    }
}
