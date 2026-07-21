namespace Shopping.Infrastructure.Storage;

using System.Net;

internal static class ProductImageBlobSeedData
{
    public static readonly ProductImageBlobSeed[] Items =
    [
        .. CreateSeeds("starter-coffee", "Starter Coffee", "#f4efe6", "#7c4a2d"),
        .. CreateSeeds("ceramic-mug", "Ceramic Mug", "#e9f2f7", "#25637a"),
        .. CreateSeeds("travel-tumbler", "Travel Tumbler", "#eef0f3", "#59606a"),
        .. CreateSeeds("espresso-beans", "Espresso Beans", "#f0e7dc", "#4b2f22"),
        .. CreateSeeds("breakfast-tea", "Breakfast Tea", "#f6eee1", "#8a4f19"),
        .. CreateSeeds("glass-teapot", "Glass Teapot", "#eaf6f3", "#247c6d"),
        .. CreateSeeds("pour-over-kit", "Pour Over Kit", "#f1efe9", "#5d5a45"),
        .. CreateSeeds("milk-frother", "Milk Frother", "#eef3f8", "#3f6f9f"),
        .. CreateSeeds("coffee-filters", "Coffee Filters", "#f7f4ec", "#8a7a58"),
        .. CreateSeeds("cold-brew-bottle", "Cold Brew Bottle", "#e8f0f6", "#2d5974"),
        .. CreateSeeds("digital-scale", "Digital Scale", "#f0f2f4", "#3d4852"),
        .. CreateSeeds("gift-card", "Gift Card", "#f6edf2", "#9b3567")
    ];

    private static ProductImageBlobSeed[] CreateSeeds(string productId,
                                                       string productName,
                                                       string background,
                                                       string accent)
    {
        return
        [
            new($"products/{productId}.svg", productName, background, accent),
            new($"products/{productId}-detail.svg", $"{productName} Detail", accent, background),
            new($"products/{productId}-lifestyle.svg", $"{productName} Lifestyle", "#ffffff", accent)
        ];
    }

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
