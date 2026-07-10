using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Shopping.Domain.Security;

namespace Shopping.Api.Controllers;

[ApiController]
[Route("api/admin/products")]
[Authorize(Policy = ShoppingPolicies.CatalogManagement)]
public sealed class AdminProductsController : ControllerBase
{
    [HttpGet]
    public IActionResult GetProductsForAdministration()
    {
        return Ok(Array.Empty<object>());
    }
}
