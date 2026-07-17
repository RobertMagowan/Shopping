namespace Shopping.Api.Controllers;

using Contracts.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/admin/products")]
[Authorize(Policy = ShoppingPolicies.CatalogManagement)]
public sealed class AdminProductsController : ControllerBase
{
    [HttpGet]
    public IActionResult GetProductsForAdministration() { return Ok(Array.Empty<object>()); }
}