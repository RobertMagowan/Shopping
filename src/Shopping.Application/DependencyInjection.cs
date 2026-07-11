using Microsoft.Extensions.DependencyInjection;
using Shopping.Application.Catalog;

namespace Shopping.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddShoppingApplication(this IServiceCollection services)
    {
        services.AddScoped<IGetPublishedProductsQuery, GetPublishedProductsQuery>();
        return services;
    }
}
