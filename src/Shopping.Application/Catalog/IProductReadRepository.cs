namespace Shopping.Application.Catalog;

using Domain.Catalog;

public interface IProductReadRepository
{
    Task<IReadOnlyCollection<Product>> GetPublishedProductsAsync(CancellationToken cancellationToken);
}