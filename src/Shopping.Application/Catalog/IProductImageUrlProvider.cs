namespace Shopping.Application.Catalog;

public interface IProductImageUrlProvider
{
    Task<string?> GetImageUrlAsync(string? blobName,
                                   CancellationToken cancellationToken);
}
