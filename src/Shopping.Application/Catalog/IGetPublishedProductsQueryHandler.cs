namespace Shopping.Application.Catalog;

using Contracts.Catalog;

public interface IGetPublishedProductsQueryHandler
{
    Task<IReadOnlyCollection<ProductDto>> HandleAsync(GetPublishedProductsQuery query,
                                                      CancellationToken cancellationToken);
}