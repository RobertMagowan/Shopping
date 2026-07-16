namespace Shopping.Application.Catalog;

public interface IProductImageUrlProvider
{
    string? GetImageUrl(string? blobName);
}