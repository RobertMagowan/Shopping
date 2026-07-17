namespace Shopping.Application;

using Catalog;
using Microsoft.Extensions.DependencyInjection;

public static class DependencyInjection
{
    public static IServiceCollection AddShoppingApplication(this IServiceCollection services)
    {
        services.AddScoped<IGetPublishedProductsQueryHandler, GetPublishedProductsQueryHandler>();
        return services;
    }
}