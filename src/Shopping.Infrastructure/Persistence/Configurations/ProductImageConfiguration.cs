namespace Shopping.Infrastructure.Persistence.Configurations;

using Domain.Catalog;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

public sealed class ProductImageConfiguration : IEntityTypeConfiguration<ProductImage>
{
    public void Configure(EntityTypeBuilder<ProductImage> entity)
    {
        entity.ToTable("ProductImages");
        entity.HasKey(image => image.Id);
        entity.Property(image => image.Id).HasMaxLength(128);
        entity.Property<string>("ProductId").HasMaxLength(128).IsRequired();
        entity.Property(image => image.BlobName).HasMaxLength(512).IsRequired();
        entity.Property(image => image.AltText).HasMaxLength(200).IsRequired();
        entity.Property(image => image.DisplayOrder).IsRequired();
        entity.Property(image => image.IsPrimary).IsRequired();

        entity.HasOne<Product>()
              .WithMany(product => product.Images)
              .HasForeignKey("ProductId")
              .OnDelete(DeleteBehavior.Cascade);

        entity.HasIndex("ProductId", nameof(ProductImage.DisplayOrder));
        entity.HasData(CatalogSeedData.ProductImages);
    }
}