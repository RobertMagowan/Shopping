using Microsoft.EntityFrameworkCore;
using Shopping.Infrastructure.Persistence.Entities;

namespace Shopping.Infrastructure.Persistence;

public sealed class ShoppingDbContext(DbContextOptions<ShoppingDbContext> options) : DbContext(options)
{
    public DbSet<ProductEntity> Products => Set<ProductEntity>();

    public DbSet<ProductImageEntity> ProductImages => Set<ProductImageEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ConfigureProducts(modelBuilder);
        ConfigureProductImages(modelBuilder);
        SeedCatalog(modelBuilder);
    }

    private static void ConfigureProducts(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ProductEntity>(entity =>
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
        });
    }

    private static void ConfigureProductImages(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ProductImageEntity>(entity =>
        {
            entity.ToTable("ProductImages");
            entity.HasKey(image => image.Id);
            entity.Property(image => image.Id).HasMaxLength(128);
            entity.Property(image => image.ProductId).HasMaxLength(128).IsRequired();
            entity.Property(image => image.BlobName).HasMaxLength(512).IsRequired();
            entity.Property(image => image.AltText).HasMaxLength(200).IsRequired();
            entity.Property(image => image.DisplayOrder).IsRequired();
            entity.Property(image => image.IsPrimary).IsRequired();

            entity.HasOne(image => image.Product)
                .WithMany(product => product.Images)
                .HasForeignKey(image => image.ProductId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(image => new { image.ProductId, image.DisplayOrder });
        });
    }

    private static void SeedCatalog(ModelBuilder modelBuilder)
    {
        var seedTime = new DateTimeOffset(2026, 7, 9, 0, 0, 0, TimeSpan.Zero);

        modelBuilder.Entity<ProductEntity>().HasData(
            CreateProduct("starter-coffee", "Starter Coffee", "A balanced ground coffee for everyday brewing.", 8.99m, 100, seedTime),
            CreateProduct("ceramic-mug", "Ceramic Mug", "A durable ceramic mug for hot drinks.", 12.50m, 50, seedTime),
            CreateProduct("travel-tumbler", "Travel Tumbler", "A stainless steel tumbler for drinks on the move.", 18.00m, 40, seedTime),
            CreateProduct("espresso-beans", "Espresso Beans", "Whole beans roasted for a rich espresso profile.", 11.25m, 120, seedTime),
            CreateProduct("breakfast-tea", "Breakfast Tea", "A strong black tea blend for morning brewing.", 6.75m, 90, seedTime),
            CreateProduct("glass-teapot", "Glass Teapot", "A clear teapot with an infuser for loose leaf tea.", 24.99m, 25, seedTime),
            CreateProduct("pour-over-kit", "Pour Over Kit", "A starter kit for manual pour over coffee.", 29.50m, 30, seedTime),
            CreateProduct("milk-frother", "Milk Frother", "A compact electric frother for milk and alternatives.", 16.99m, 45, seedTime),
            CreateProduct("coffee-filters", "Coffee Filters", "Compostable paper filters for pour over brewing.", 4.25m, 200, seedTime),
            CreateProduct("cold-brew-bottle", "Cold Brew Bottle", "A glass bottle with filter for overnight cold brew.", 21.00m, 20, seedTime),
            CreateProduct("digital-scale", "Digital Scale", "A precise kitchen scale for consistent brewing.", 19.95m, 35, seedTime),
            CreateProduct("gift-card", "Gift Card", "A digital gift card for the online shop.", 25.00m, 999, seedTime));

        modelBuilder.Entity<ProductImageEntity>().HasData(
            CreateImage("starter-coffee", "Starter Coffee"),
            CreateImage("ceramic-mug", "Ceramic Mug"),
            CreateImage("travel-tumbler", "Travel Tumbler"),
            CreateImage("espresso-beans", "Espresso Beans"),
            CreateImage("breakfast-tea", "Breakfast Tea"),
            CreateImage("glass-teapot", "Glass Teapot"),
            CreateImage("pour-over-kit", "Pour Over Kit"),
            CreateImage("milk-frother", "Milk Frother"),
            CreateImage("coffee-filters", "Coffee Filters"),
            CreateImage("cold-brew-bottle", "Cold Brew Bottle"),
            CreateImage("digital-scale", "Digital Scale"),
            CreateImage("gift-card", "Gift Card"));
    }

    private static ProductEntity CreateProduct(
        string id,
        string name,
        string description,
        decimal priceAmount,
        int stockQuantity,
        DateTimeOffset seedTime)
    {
        return new ProductEntity
        {
            Id = id,
            Slug = id,
            Name = name,
            Description = description,
            PriceAmount = priceAmount,
            Currency = "GBP",
            IsAvailable = true,
            StockQuantity = stockQuantity,
            IsPublished = true,
            CreatedUtc = seedTime,
            UpdatedUtc = seedTime
        };
    }

    private static ProductImageEntity CreateImage(string productId, string productName)
    {
        return new ProductImageEntity
        {
            Id = $"{productId}-primary",
            ProductId = productId,
            BlobName = $"products/{productId}.svg",
            AltText = $"{productName} product image",
            DisplayOrder = 0,
            IsPrimary = true
        };
    }
}
