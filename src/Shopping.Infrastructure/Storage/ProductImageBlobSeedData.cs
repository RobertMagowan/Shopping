namespace Shopping.Infrastructure.Storage;

using System.Net;

internal static class ProductImageBlobSeedData
{
    public static readonly ProductImageBlobSeed[] Items =
    [
        new("products/starter-coffee.svg", "Starter Coffee", "#f4efe6", "#7c4a2d"),
        new("products/ceramic-mug.svg", "Ceramic Mug", "#e9f2f7", "#25637a"),
        new("products/travel-tumbler.svg", "Travel Tumbler", "#eef0f3", "#59606a"),
        new("products/espresso-beans.svg", "Espresso Beans", "#f0e7dc", "#4b2f22"),
        new("products/breakfast-tea.svg", "Breakfast Tea", "#f6eee1", "#8a4f19"),
        new("products/glass-teapot.svg", "Glass Teapot", "#eaf6f3", "#247c6d"),
        new("products/pour-over-kit.svg", "Pour Over Kit", "#f1efe9", "#5d5a45"),
        new("products/milk-frother.svg", "Milk Frother", "#eef3f8", "#3f6f9f"),
        new("products/coffee-filters.svg", "Coffee Filters", "#f7f4ec", "#8a7a58"),
        new("products/cold-brew-bottle.svg", "Cold Brew Bottle", "#e8f0f6", "#2d5974"),
        new("products/digital-scale.svg", "Digital Scale", "#f0f2f4", "#3d4852"),
        new("products/gift-card.svg", "Gift Card", "#f6edf2", "#9b3567")
    ];

    public static string CreateSvg(ProductImageBlobSeed seed)
    {
        var productName = WebUtility.HtmlEncode(seed.ProductName);

        return $$"""
                 <svg xmlns="http://www.w3.org/2000/svg" width="640" height="420" viewBox="0 0 640 420" role="img" aria-label="{{productName}}">
                   <rect width="640" height="420" fill="{{seed.Background}}"/>
                   <rect x="54" y="54" width="532" height="312" rx="18" fill="#ffffff" opacity="0.82"/>
                   <circle cx="160" cy="162" r="62" fill="{{seed.Accent}}" opacity="0.92"/>
                   <rect x="250" y="132" width="248" height="18" rx="9" fill="{{seed.Accent}}" opacity="0.72"/>
                   <rect x="250" y="172" width="190" height="14" rx="7" fill="{{seed.Accent}}" opacity="0.42"/>
                   <rect x="250" y="204" width="220" height="14" rx="7" fill="{{seed.Accent}}" opacity="0.30"/>
                   <text x="54" y="394" font-family="Arial, Helvetica, sans-serif" font-size="30" font-weight="700" fill="#1f2933">{{productName}}</text>
                 </svg>
                 """;
    }
}