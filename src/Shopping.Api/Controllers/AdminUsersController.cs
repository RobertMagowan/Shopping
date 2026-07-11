using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Shopping.Contracts.Security;

namespace Shopping.Api.Controllers;

[ApiController]
[Route("api/admin/users")]
[Authorize(Policy = ShoppingPolicies.AdminAccess)]
public sealed class AdminUsersController : ControllerBase
{
    [HttpGet]
    public IActionResult GetUsers()
    {
        return Ok(Array.Empty<object>());
    }
}
