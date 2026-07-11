using Microsoft.EntityFrameworkCore;
using Shopping.Domain.Catalog;
using Shopping.Infrastructure.Persistence.Configurations;

namespace Shopping.Infrastructure.Persistence;

public sealed class ShoppingDbContext(DbContextOptions<ShoppingDbContext> options) : DbContext(options)
{
    public DbSet<Product> Products => Set<Product>();

    public DbSet<ProductImage> ProductImages => Set<ProductImage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfiguration(new ProductConfiguration());
        modelBuilder.ApplyConfiguration(new ProductImageConfiguration());
    }
}
