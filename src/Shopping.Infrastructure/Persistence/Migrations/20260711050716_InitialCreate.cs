using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Shopping.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Products",
                columns: table => new
                {
                    Id = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    Slug = table.Column<string>(type: "nvarchar(160)", maxLength: 160, nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(2000)", maxLength: 2000, nullable: false),
                    PriceAmount = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: false),
                    Currency = table.Column<string>(type: "nvarchar(3)", maxLength: 3, nullable: false),
                    IsAvailable = table.Column<bool>(type: "bit", nullable: false),
                    StockQuantity = table.Column<int>(type: "int", nullable: false),
                    IsPublished = table.Column<bool>(type: "bit", nullable: false),
                    CreatedUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    UpdatedUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Products", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ProductImages",
                columns: table => new
                {
                    Id = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    BlobName = table.Column<string>(type: "nvarchar(512)", maxLength: 512, nullable: false),
                    AltText = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    DisplayOrder = table.Column<int>(type: "int", nullable: false),
                    IsPrimary = table.Column<bool>(type: "bit", nullable: false),
                    ProductId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ProductImages", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductImages_Products_ProductId",
                        column: x => x.ProductId,
                        principalTable: "Products",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "Products",
                columns: new[] { "Id", "CreatedUtc", "Currency", "Description", "IsAvailable", "IsPublished", "Name", "PriceAmount", "Slug", "StockQuantity", "UpdatedUtc" },
                values: new object[,]
                {
                    { "breakfast-tea", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A strong black tea blend for morning brewing.", true, true, "Breakfast Tea", 6.75m, "breakfast-tea", 90, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "ceramic-mug", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A durable ceramic mug for hot drinks.", true, true, "Ceramic Mug", 12.50m, "ceramic-mug", 50, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "coffee-filters", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "Compostable paper filters for pour over brewing.", true, true, "Coffee Filters", 4.25m, "coffee-filters", 200, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "cold-brew-bottle", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A glass bottle with filter for overnight cold brew.", true, true, "Cold Brew Bottle", 21.00m, "cold-brew-bottle", 20, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "digital-scale", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A precise kitchen scale for consistent brewing.", true, true, "Digital Scale", 19.95m, "digital-scale", 35, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "espresso-beans", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "Whole beans roasted for a rich espresso profile.", true, true, "Espresso Beans", 11.25m, "espresso-beans", 120, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "gift-card", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A digital gift card for the online shop.", true, true, "Gift Card", 25.00m, "gift-card", 999, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "glass-teapot", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A clear teapot with an infuser for loose leaf tea.", true, true, "Glass Teapot", 24.99m, "glass-teapot", 25, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "milk-frother", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A compact electric frother for milk and alternatives.", true, true, "Milk Frother", 16.99m, "milk-frother", 45, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "pour-over-kit", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A starter kit for manual pour over coffee.", true, true, "Pour Over Kit", 29.50m, "pour-over-kit", 30, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "starter-coffee", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A balanced ground coffee for everyday brewing.", true, true, "Starter Coffee", 8.99m, "starter-coffee", 100, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) },
                    { "travel-tumbler", new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)), "GBP", "A stainless steel tumbler for drinks on the move.", true, true, "Travel Tumbler", 18.00m, "travel-tumbler", 40, new DateTimeOffset(new DateTime(2026, 7, 9, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)) }
                });

            migrationBuilder.InsertData(
                table: "ProductImages",
                columns: new[] { "Id", "AltText", "BlobName", "DisplayOrder", "IsPrimary", "ProductId" },
                values: new object[,]
                {
                    { "breakfast-tea-detail", "Breakfast Tea detail product image", "products/breakfast-tea-detail.svg", 1, false, "breakfast-tea" },
                    { "breakfast-tea-lifestyle", "Breakfast Tea lifestyle product image", "products/breakfast-tea-lifestyle.svg", 2, false, "breakfast-tea" },
                    { "breakfast-tea-primary", "Breakfast Tea primary product image", "products/breakfast-tea.svg", 0, true, "breakfast-tea" },
                    { "ceramic-mug-detail", "Ceramic Mug detail product image", "products/ceramic-mug-detail.svg", 1, false, "ceramic-mug" },
                    { "ceramic-mug-lifestyle", "Ceramic Mug lifestyle product image", "products/ceramic-mug-lifestyle.svg", 2, false, "ceramic-mug" },
                    { "ceramic-mug-primary", "Ceramic Mug primary product image", "products/ceramic-mug.svg", 0, true, "ceramic-mug" },
                    { "coffee-filters-detail", "Coffee Filters detail product image", "products/coffee-filters-detail.svg", 1, false, "coffee-filters" },
                    { "coffee-filters-lifestyle", "Coffee Filters lifestyle product image", "products/coffee-filters-lifestyle.svg", 2, false, "coffee-filters" },
                    { "coffee-filters-primary", "Coffee Filters primary product image", "products/coffee-filters.svg", 0, true, "coffee-filters" },
                    { "cold-brew-bottle-detail", "Cold Brew Bottle detail product image", "products/cold-brew-bottle-detail.svg", 1, false, "cold-brew-bottle" },
                    { "cold-brew-bottle-lifestyle", "Cold Brew Bottle lifestyle product image", "products/cold-brew-bottle-lifestyle.svg", 2, false, "cold-brew-bottle" },
                    { "cold-brew-bottle-primary", "Cold Brew Bottle primary product image", "products/cold-brew-bottle.svg", 0, true, "cold-brew-bottle" },
                    { "digital-scale-detail", "Digital Scale detail product image", "products/digital-scale-detail.svg", 1, false, "digital-scale" },
                    { "digital-scale-lifestyle", "Digital Scale lifestyle product image", "products/digital-scale-lifestyle.svg", 2, false, "digital-scale" },
                    { "digital-scale-primary", "Digital Scale primary product image", "products/digital-scale.svg", 0, true, "digital-scale" },
                    { "espresso-beans-detail", "Espresso Beans detail product image", "products/espresso-beans-detail.svg", 1, false, "espresso-beans" },
                    { "espresso-beans-lifestyle", "Espresso Beans lifestyle product image", "products/espresso-beans-lifestyle.svg", 2, false, "espresso-beans" },
                    { "espresso-beans-primary", "Espresso Beans primary product image", "products/espresso-beans.svg", 0, true, "espresso-beans" },
                    { "gift-card-detail", "Gift Card detail product image", "products/gift-card-detail.svg", 1, false, "gift-card" },
                    { "gift-card-lifestyle", "Gift Card lifestyle product image", "products/gift-card-lifestyle.svg", 2, false, "gift-card" },
                    { "gift-card-primary", "Gift Card primary product image", "products/gift-card.svg", 0, true, "gift-card" },
                    { "glass-teapot-detail", "Glass Teapot detail product image", "products/glass-teapot-detail.svg", 1, false, "glass-teapot" },
                    { "glass-teapot-lifestyle", "Glass Teapot lifestyle product image", "products/glass-teapot-lifestyle.svg", 2, false, "glass-teapot" },
                    { "glass-teapot-primary", "Glass Teapot primary product image", "products/glass-teapot.svg", 0, true, "glass-teapot" },
                    { "milk-frother-detail", "Milk Frother detail product image", "products/milk-frother-detail.svg", 1, false, "milk-frother" },
                    { "milk-frother-lifestyle", "Milk Frother lifestyle product image", "products/milk-frother-lifestyle.svg", 2, false, "milk-frother" },
                    { "milk-frother-primary", "Milk Frother primary product image", "products/milk-frother.svg", 0, true, "milk-frother" },
                    { "pour-over-kit-detail", "Pour Over Kit detail product image", "products/pour-over-kit-detail.svg", 1, false, "pour-over-kit" },
                    { "pour-over-kit-lifestyle", "Pour Over Kit lifestyle product image", "products/pour-over-kit-lifestyle.svg", 2, false, "pour-over-kit" },
                    { "pour-over-kit-primary", "Pour Over Kit primary product image", "products/pour-over-kit.svg", 0, true, "pour-over-kit" },
                    { "starter-coffee-detail", "Starter Coffee detail product image", "products/starter-coffee-detail.svg", 1, false, "starter-coffee" },
                    { "starter-coffee-lifestyle", "Starter Coffee lifestyle product image", "products/starter-coffee-lifestyle.svg", 2, false, "starter-coffee" },
                    { "starter-coffee-primary", "Starter Coffee primary product image", "products/starter-coffee.svg", 0, true, "starter-coffee" },
                    { "travel-tumbler-detail", "Travel Tumbler detail product image", "products/travel-tumbler-detail.svg", 1, false, "travel-tumbler" },
                    { "travel-tumbler-lifestyle", "Travel Tumbler lifestyle product image", "products/travel-tumbler-lifestyle.svg", 2, false, "travel-tumbler" },
                    { "travel-tumbler-primary", "Travel Tumbler primary product image", "products/travel-tumbler.svg", 0, true, "travel-tumbler" }
                });

            migrationBuilder.CreateIndex(
                name: "IX_ProductImages_ProductId_DisplayOrder",
                table: "ProductImages",
                columns: new[] { "ProductId", "DisplayOrder" });

            migrationBuilder.CreateIndex(
                name: "IX_Products_Slug",
                table: "Products",
                column: "Slug",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ProductImages");

            migrationBuilder.DropTable(
                name: "Products");
        }
    }
}
