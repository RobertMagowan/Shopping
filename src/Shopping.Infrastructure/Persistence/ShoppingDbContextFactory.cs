namespace Shopping.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

public sealed class ShoppingDbContextFactory : IDesignTimeDbContextFactory<ShoppingDbContext>
{
    public ShoppingDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ShoppingDbContext>()
                      .UseSqlServer("Server=localhost;Database=ShoppingDesignTime;Integrated Security=true;TrustServerCertificate=true")
                      .Options;

        return new ShoppingDbContext(options);
    }
}
