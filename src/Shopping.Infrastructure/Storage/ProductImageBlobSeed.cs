namespace Shopping.Infrastructure.Storage;

public sealed record ProductImageBlobSeed(
    string BlobName,
    string ProductName,
    string Background,
    string Accent);
