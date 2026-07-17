using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using Shopping.Contracts.Security;
using Shopping.Web.Components;
using Shopping.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpsRedirection(options => { options.HttpsPort = 7262; });

var redisConnectionString = builder.Configuration["ShoppingAzure:Redis:ConnectionString"];

if (string.IsNullOrWhiteSpace(redisConnectionString))
{
    throw new InvalidOperationException("Missing configuration value 'ShoppingAzure:Redis:ConnectionString'. " +
                                        "Shopping.Web uses Redis for distributed token caching.");
}

builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = redisConnectionString;
    options.InstanceName = "Shopping.Web:";
});

builder.Services
       .AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
       .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("EntraExternalId"))
       .EnableTokenAcquisitionToCallDownstreamApi()
       .AddDistributedTokenCaches();

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(ShoppingPolicies.AdminAccess, policy =>
                          policy.RequireRole(ShoppingRoles.Admin));

    options.AddPolicy(ShoppingPolicies.CustomerAccess, policy =>
                          policy.RequireRole(ShoppingRoles.Customer, ShoppingRoles.Admin));

    options.AddPolicy(ShoppingPolicies.CatalogManagement, policy =>
                          policy.RequireRole(ShoppingRoles.CatalogManager, ShoppingRoles.Admin));
});

builder.Services.AddCascadingAuthenticationState();
builder.Services.AddControllersWithViews()
       .AddMicrosoftIdentityUI();

builder.Services.AddDownstreamApi("ShoppingApi",
                                  builder.Configuration.GetSection("ShoppingApi"));

builder.Services.AddHttpClient("ShoppingApi.Public", client =>
{
    var baseUrl = builder.Configuration["ShoppingApi:BaseUrl"];

    if (string.IsNullOrWhiteSpace(baseUrl))
    {
        throw new InvalidOperationException("Missing configuration value 'ShoppingApi:BaseUrl'.");
    }

    client.BaseAddress = new Uri(baseUrl);
});

builder.Services.AddScoped<ShoppingApiClient>();
builder.Services.AddHealthChecks();

builder.Services.AddRazorComponents()
       .AddInteractiveServerComponents();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", true);
    app.UseHsts();
}

app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();
app.UseAntiforgery();

app.MapStaticAssets();
app.MapHealthChecks("/healthz");
app.MapControllers();
app.MapRazorComponents<App>()
   .AddInteractiveServerRenderMode();

app.Run();
