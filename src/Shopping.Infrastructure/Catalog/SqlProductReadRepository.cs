namespace Shopping.Infrastructure.Catalog;

using Application.Catalog;
using Domain.Catalog;
using Microsoft.EntityFrameworkCore;
using Persistence;

public sealed class SqlProductReadRepository(ShoppingDbContext dbContext) : IProductReadRepository
{
    public async Task<IReadOnlyCollection<Product>> GetPublishedProductsAsync(CancellationToken cancellationToken)
    {
        var products = await dbContext.Products
                                      .AsNoTracking()
                                      .Include(product => product.Images)
                                      .Where(product => product.IsPublished)
                                      .ToArrayAsync(cancellationToken);

        return products;
    }
}