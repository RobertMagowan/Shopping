using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Shopping.Application.Catalog;

namespace Shopping.Api.Controllers;

[ApiController]
[Route("api/products")]
public sealed class ProductsController(IProductCatalog productCatalog) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<ProductDto>>> GetProducts(CancellationToken cancellationToken)
    {
        var products = await productCatalog.GetPublishedProductsAsync(cancellationToken);
        return Ok(products);
    }
}
