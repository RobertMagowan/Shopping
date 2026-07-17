namespace Shopping.Infrastructure.Persistence.Configurations;

using Domain.Catalog;

internal static class CatalogSeedData
{
    private static readonly DateTimeOffset SeedTime = new(2026, 7, 9, 0, 0, 0, TimeSpan.Zero);

    public static readonly Product[] Products =
    [
        CreateProduct("starter-coffee", "Starter Coffee", "A balanced ground coffee for everyday brewing.", 8.99m, 100),
        CreateProduct("ceramic-mug", "Ceramic Mug", "A durable ceramic mug for hot drinks.", 12.50m, 50),
        CreateProduct("travel-tumbler", "Travel Tumbler", "A stainless steel tumbler for drinks on the move.", 18.00m, 40),
        CreateProduct("espresso-beans", "Espresso Beans", "Whole beans roasted for a rich espresso profile.", 11.25m, 120),
        CreateProduct("breakfast-tea", "Breakfast Tea", "A strong black tea blend for morning brewing.", 6.75m, 90),
        CreateProduct("glass-teapot", "Glass Teapot", "A clear teapot with an infuser for loose leaf tea.", 24.99m, 25),
        CreateProduct("pour-over-kit", "Pour Over Kit", "A starter kit for manual pour over coffee.", 29.50m, 30),
        CreateProduct("milk-frother", "Milk Frother", "A compact electric frother for milk and alternatives.", 16.99m, 45),
        CreateProduct("coffee-filters", "Coffee Filters", "Compostable paper filters for pour over brewing.", 4.25m, 200),
        CreateProduct("cold-brew-bottle", "Cold Brew Bottle", "A glass bottle with filter for overnight cold brew.", 21.00m, 20),
        CreateProduct("digital-scale", "Digital Scale", "A precise kitchen scale for consistent brewing.", 19.95m, 35),
        CreateProduct("gift-card", "Gift Card", "A digital gift card for the online shop.", 25.00m, 999)
    ];

    public static readonly object[] ProductImages =
    [
        CreateImageSeed("starter-coffee", "Starter Coffee"),
        CreateImageSeed("ceramic-mug", "Ceramic Mug"),
        CreateImageSeed("travel-tumbler", "Travel Tumbler"),
        CreateImageSeed("espresso-beans", "Espresso Beans"),
        CreateImageSeed("breakfast-tea", "Breakfast Tea"),
        CreateImageSeed("glass-teapot", "Glass Teapot"),
        CreateImageSeed("pour-over-kit", "Pour Over Kit"),
        CreateImageSeed("milk-frother", "Milk Frother"),
        CreateImageSeed("coffee-filters", "Coffee Filters"),
        CreateImageSeed("cold-brew-bottle", "Cold Brew Bottle"),
        CreateImageSeed("digital-scale", "Digital Scale"),
        CreateImageSeed("gift-card", "Gift Card")
    ];

    private static Product CreateProduct(string id,
                                         string name,
                                         string description,
                                         decimal priceAmount,
                                         int stockQuantity)
    {
        return new Product
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
            CreatedUtc = SeedTime,
            UpdatedUtc = SeedTime
        };
    }

    private static object CreateImageSeed(string productId, string productName)
    {
        return new
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