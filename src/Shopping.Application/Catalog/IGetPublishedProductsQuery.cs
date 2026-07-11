using Shopping.Contracts.Catalog;

namespace Shopping.Application.Catalog;

public interface IGetPublishedProductsQuery
{
    Task<IReadOnlyCollection<ProductDto>> ExecuteAsync(CancellationToken cancellationToken);
}
