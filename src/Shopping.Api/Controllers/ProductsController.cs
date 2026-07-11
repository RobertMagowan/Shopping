using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Shopping.Application.Catalog;
using Shopping.Contracts.Catalog;

namespace Shopping.Api.Controllers;

[ApiController]
[Route("api/products")]
public sealed class ProductsController(IGetPublishedProductsQuery getPublishedProductsQuery) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<ProductDto>>> GetProducts(CancellationToken cancellationToken)
    {
        var products = await getPublishedProductsQuery.ExecuteAsync(cancellationToken);
        return Ok(products);
    }
}
