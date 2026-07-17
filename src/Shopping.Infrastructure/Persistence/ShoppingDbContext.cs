namespace Shopping.Infrastructure.Persistence;

using Configurations;
using Domain.Catalog;
using Microsoft.EntityFrameworkCore;

public sealed class ShoppingDbContext(DbContextOptions<ShoppingDbContext> options) : DbContext(options)
{
    public DbSet<Product> Products { get => Set<Product>(); }

    public DbSet<ProductImage> ProductImages { get => Set<ProductImage>(); }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfiguration(new ProductConfiguration());
        modelBuilder.ApplyConfiguration(new ProductImageConfiguration());
    }
}