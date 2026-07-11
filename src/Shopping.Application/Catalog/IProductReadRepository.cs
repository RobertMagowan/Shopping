using Shopping.Domain.Catalog;

namespace Shopping.Application.Catalog;

public interface IProductReadRepository
{
    Task<IReadOnlyCollection<Product>> GetPublishedProductsAsync(CancellationToken cancellationToken);
}
