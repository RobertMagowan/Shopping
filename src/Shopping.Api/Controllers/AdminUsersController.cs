namespace Shopping.Api.Controllers;

using Contracts.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/admin/users")]
[Authorize(Policy = ShoppingPolicies.AdminAccess)]
public sealed class AdminUsersController : ControllerBase
{
    [HttpGet]
    public IActionResult GetUsers() { return Ok(Array.Empty<object>()); }
}