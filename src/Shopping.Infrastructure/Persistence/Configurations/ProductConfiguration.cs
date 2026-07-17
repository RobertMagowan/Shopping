namespace Shopping.Infrastructure.Persistence.Configurations;

using Domain.Catalog;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

public sealed class ProductConfiguration : IEntityTypeConfiguration<Product>
{
    public void Configure(EntityTypeBuilder<Product> entity)
    {
        entity.ToTable("Products");
        entity.HasKey(product => product.Id);
        entity.Property(product => product.Id).HasMaxLength(128);
        entity.Property(product => product.Slug).HasMaxLength(160).IsRequired();
        entity.Property(product => product.Name).HasMaxLength(200).IsRequired();
        entity.Property(product => product.Description).HasMaxLength(2000).IsRequired();
        entity.Property(product => product.PriceAmount).HasPrecision(18, 2);
        entity.Property(product => product.Currency).HasMaxLength(3).IsRequired();
        entity.Property(product => product.IsAvailable).IsRequired();
        entity.Property(product => product.StockQuantity).IsRequired();
        entity.Property(product => product.IsPublished).IsRequired();
        entity.Property(product => product.CreatedUtc).IsRequired();
        entity.Property(product => product.UpdatedUtc).IsRequired();

        entity.HasIndex(product => product.Slug).IsUnique();
        entity.HasData(CatalogSeedData.Products);
    }
}