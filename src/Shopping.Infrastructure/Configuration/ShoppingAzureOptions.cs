namespace Shopping.Infrastructure.Configuration;

public sealed class ShoppingAzureOptions
{
    public const string SectionName = "ShoppingAzure";

    public StorageOptions Storage { get; init; } = new();

    public RedisOptions Redis { get; init; } = new();

    public ServiceBusOptions ServiceBus { get; init; } = new();
}

public sealed class StorageOptions
{
    public string ConnectionString { get; init; } = "";

    public string ProductImagesContainer { get; init; } = "product-images";
}

public sealed class RedisOptions
{
    public string ConnectionString { get; init; } = "";
}

public sealed class ServiceBusOptions
{
    public string ConnectionString { get; init; } = "";

    public string CartEventsQueue { get; init; } = "cart-events";

    public string OrdersTopic { get; init; } = "orders";
}
