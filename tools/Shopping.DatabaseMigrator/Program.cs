using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Shopping.Infrastructure.Persistence;

var connectionString = GetRequiredEnvironmentVariable("ConnectionStrings__ShoppingDatabase");
var accessToken = GetRequiredEnvironmentVariable("AZURE_SQL_ACCESS_TOKEN");
var apiPrincipalId = Guid.Parse(GetRequiredEnvironmentVariable("SHOPPING_API_PRINCIPAL_ID"));
var apiPrincipalName = GetRequiredEnvironmentVariable("SHOPPING_API_PRINCIPAL_NAME");

await using var connection = new SqlConnection(connectionString)
{
    AccessToken = accessToken
};
var options = new DbContextOptionsBuilder<ShoppingDbContext>()
    .UseSqlServer(connection, sqlServerOptions => sqlServerOptions.EnableRetryOnFailure())
    .Options;

await using var dbContext = new ShoppingDbContext(options);
await dbContext.Database.MigrateAsync();

var escapedPrincipalName = apiPrincipalName.Replace("]", "]]", StringComparison.Ordinal);
var principalSid = Convert.ToHexString(apiPrincipalId.ToByteArray());
var principalSql = $"""
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE sid = 0x{principalSid})
    BEGIN
        CREATE USER [{escapedPrincipalName}] WITH SID = 0x{principalSid}, TYPE = E;
    END;

    IF IS_ROLEMEMBER('db_datareader', '{apiPrincipalName.Replace("'", "''", StringComparison.Ordinal)}') <> 1
        ALTER ROLE db_datareader ADD MEMBER [{escapedPrincipalName}];

    IF IS_ROLEMEMBER('db_datawriter', '{apiPrincipalName.Replace("'", "''", StringComparison.Ordinal)}') <> 1
        ALTER ROLE db_datawriter ADD MEMBER [{escapedPrincipalName}];
    """;

await dbContext.Database.ExecuteSqlRawAsync(principalSql);
Console.WriteLine("Database migrations and API managed-identity permissions are current.");

static string GetRequiredEnvironmentVariable(string name)
{
    var value = Environment.GetEnvironmentVariable(name);

    if (string.IsNullOrWhiteSpace(value))
    {
        throw new InvalidOperationException($"Environment variable '{name}' is required.");
    }

    return value;
}
