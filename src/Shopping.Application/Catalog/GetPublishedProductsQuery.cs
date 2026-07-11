using Shopping.Contracts.Catalog;
using Shopping.Domain.Catalog;

namespace Shopping.Application.Catalog;

public sealed class GetPublishedProductsQuery(
    IProductReadRepository productReadRepository,
    IProductImageUrlProvider productImageUrlProvider) : IGetPublishedProductsQuery
{
    public async Task<IReadOnlyCollection<ProductDto>> ExecuteAsync(CancellationToken cancellationToken)
    {
        var products = await productReadRepository.GetPublishedProductsAsync(cancellationToken);

        return products
            .OrderBy(product => product.Name)
            .Select(ToDto)
            .ToArray();
    }

    private ProductDto ToDto(Product product)
    {
        return new ProductDto(
            product.Id,
            product.Name,
            product.Description,
            product.PriceAmount,
            product.Currency,
            product.CanBePurchased,
            productImageUrlProvider.GetImageUrl(product.PrimaryImageBlobName));
    }
}
