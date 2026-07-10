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
                    ProductId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    BlobName = table.Column<string>(type: "nvarchar(512)", maxLength: 512, nullable: false),
                    AltText = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    DisplayOrder = table.Column<int>(type: "int", nullable: false),
                    IsPrimary = table.Column<bool>(type: "bit", nullable: false)
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
                    { "breakfast-tea-primary", "Breakfast Tea product image", "products/breakfast-tea.svg", 0, true, "breakfast-tea" },
                    { "ceramic-mug-primary", "Ceramic Mug product image", "products/ceramic-mug.svg", 0, true, "ceramic-mug" },
                    { "coffee-filters-primary", "Coffee Filters product image", "products/coffee-filters.svg", 0, true, "coffee-filters" },
                    { "cold-brew-bottle-primary", "Cold Brew Bottle product image", "products/cold-brew-bottle.svg", 0, true, "cold-brew-bottle" },
                    { "digital-scale-primary", "Digital Scale product image", "products/digital-scale.svg", 0, true, "digital-scale" },
                    { "espresso-beans-primary", "Espresso Beans product image", "products/espresso-beans.svg", 0, true, "espresso-beans" },
                    { "gift-card-primary", "Gift Card product image", "products/gift-card.svg", 0, true, "gift-card" },
                    { "glass-teapot-primary", "Glass Teapot product image", "products/glass-teapot.svg", 0, true, "glass-teapot" },
                    { "milk-frother-primary", "Milk Frother product image", "products/milk-frother.svg", 0, true, "milk-frother" },
                    { "pour-over-kit-primary", "Pour Over Kit product image", "products/pour-over-kit.svg", 0, true, "pour-over-kit" },
                    { "starter-coffee-primary", "Starter Coffee product image", "products/starter-coffee.svg", 0, true, "starter-coffee" },
                    { "travel-tumbler-primary", "Travel Tumbler product image", "products/travel-tumbler.svg", 0, true, "travel-tumbler" }
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
