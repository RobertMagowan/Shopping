namespace Shopping.Api.Controllers;

using Application.Catalog;
using Contracts.Catalog;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/products")]
public sealed class ProductsController(IGetPublishedProductsQueryHandler getPublishedProductsQueryHandler) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<ProductDto>>> GetProducts(CancellationToken cancellationToken)
    {
        var products = await getPublishedProductsQueryHandler.HandleAsync(new GetPublishedProductsQuery(),
                                                                          cancellationToken);

        return Ok(products);
    }
}