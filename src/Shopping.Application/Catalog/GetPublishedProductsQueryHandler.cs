namespace Shopping.Application.Catalog;

using Contracts.Catalog;
using Domain.Catalog;

public sealed record GetPublishedProductsQuery;


public sealed class GetPublishedProductsQueryHandler(IProductReadRepository productReadRepository,
                                                     IProductImageUrlProvider productImageUrlProvider) : IGetPublishedProductsQueryHandler
{
    public async Task<IReadOnlyCollection<ProductDto>> HandleAsync(GetPublishedProductsQuery query,
                                                                   CancellationToken cancellationToken)
    {
        var products = await productReadRepository.GetPublishedProductsAsync(cancellationToken);

        return products.OrderBy(product => product.Name)
                       .Select(ToDto)
                       .ToArray();
    }

    private ProductDto ToDto(Product product)
    {
        var imageUrls = product.OrderedImageBlobNames
                               .Select(productImageUrlProvider.GetImageUrl)
                               .Where(imageUrl => !string.IsNullOrWhiteSpace(imageUrl))
                               .Select(imageUrl => imageUrl!)
                               .ToArray();

        return new ProductDto(product.Id,
                              product.Name,
                              product.Description,
                              product.PriceAmount,
                              product.Currency,
                              product.CanBePurchased,
                              productImageUrlProvider.GetImageUrl(product.PrimaryImageBlobName),
                              imageUrls);
    }
}