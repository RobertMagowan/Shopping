using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Identity.Web;
using Shopping.Application;
using Shopping.Contracts.Security;
using Shopping.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services
       .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
       .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("EntraExternalId"));

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(ShoppingPolicies.AdminAccess, policy =>
                          policy.RequireRole(ShoppingRoles.Admin));

    options.AddPolicy(ShoppingPolicies.CustomerAccess, policy =>
                          policy.RequireRole(ShoppingRoles.Customer, ShoppingRoles.Admin));

    options.AddPolicy(ShoppingPolicies.CatalogManagement, policy =>
                          policy.RequireRole(ShoppingRoles.CatalogManager, ShoppingRoles.Admin));
});

builder.Services.AddShoppingApplication();
builder.Services.AddShoppingInfrastructure(builder.Configuration, builder.Environment.IsDevelopment());
builder.Services.AddControllers();
builder.Services.AddHealthChecks()
       .AddCheck("self", () => HealthCheckResult.Healthy());

var app = builder.Build();

app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();

app.MapHealthChecks("/healthz");
app.MapControllers();

app.Run();

public partial class Program;