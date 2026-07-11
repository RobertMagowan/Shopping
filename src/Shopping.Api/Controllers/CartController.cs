using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Shopping.Contracts.Security;

namespace Shopping.Api.Controllers;

[ApiController]
[Route("api/cart")]
[Authorize(Policy = ShoppingPolicies.CustomerAccess)]
public sealed class CartController : ControllerBase
{
    [HttpPost("items")]
    public IActionResult AddItem(AddCartItemRequest request)
    {
        return Accepted(new
        {
            request.ProductId,
            request.Quantity
        });
    }
}

public sealed record AddCartItemRequest(string ProductId, int Quantity);
