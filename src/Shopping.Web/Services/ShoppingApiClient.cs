using System.Net.Http.Json;
using Shopping.Contracts.Catalog;

namespace Shopping.Web.Services;

public sealed class ShoppingApiClient(IHttpClientFactory httpClientFactory)
{
    public async Task<IReadOnlyCollection<ProductDto>> GetProductsAsync(
        CancellationToken cancellationToken = default)
    {
        var httpClient = httpClientFactory.CreateClient("ShoppingApi.Public");
        var products = await httpClient.GetFromJsonAsync<IReadOnlyCollection<ProductDto>>(
            "api/products",
            cancellationToken);

        return products ?? [];
    }
}
