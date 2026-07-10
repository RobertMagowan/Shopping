namespace Shopping.Application.Catalog;

public interface IProductCatalog
{
    Task<IReadOnlyCollection<ProductDto>> GetPublishedProductsAsync(CancellationToken cancellationToken);
}
