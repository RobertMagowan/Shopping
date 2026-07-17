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

        var productDtos = new List<ProductDto>();

        foreach (var product in products.OrderBy(product => product.Name))
        {
            productDtos.Add(await ToDtoAsync(product, cancellationToken));
        }

        return productDtos.ToArray();
    }

    private async Task<ProductDto> ToDtoAsync(Product product,
                                              CancellationToken cancellationToken)
    {
        var imageUrls = new List<string>();

        foreach (var blobName in product.OrderedImageBlobNames)
        {
            var imageUrl = await productImageUrlProvider.GetImageUrlAsync(blobName, cancellationToken);

            if (!string.IsNullOrWhiteSpace(imageUrl))
            {
                imageUrls.Add(imageUrl);
            }
        }

        return new ProductDto(product.Id,
                              product.Name,
                              product.Description,
                              product.PriceAmount,
                              product.Currency,
                              product.CanBePurchased,
                              await productImageUrlProvider.GetImageUrlAsync(product.PrimaryImageBlobName, cancellationToken),
                              imageUrls.ToArray());
    }
}
