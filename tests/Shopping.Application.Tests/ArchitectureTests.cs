namespace Shopping.Application.Tests;

using System.Reflection;
using Contracts.Catalog;
using Domain.Catalog;

public sealed class ArchitectureTests
{
    [Fact]
    public void Domain_does_not_reference_outer_layers()
    {
        var references = GetReferencedAssemblyNames(typeof(Product).Assembly);

        Assert.DoesNotContain("Shopping.Application", references);
        Assert.DoesNotContain("Shopping.Contracts", references);
        Assert.DoesNotContain("Shopping.Infrastructure", references);
        Assert.DoesNotContain("Shopping.Api", references);
        Assert.DoesNotContain("Shopping.Web", references);
    }

    [Fact]
    public void Application_does_not_reference_infrastructure_or_presentation()
    {
        var references = GetReferencedAssemblyNames(typeof(DependencyInjection).Assembly);

        Assert.DoesNotContain("Shopping.Infrastructure", references);
        Assert.DoesNotContain("Shopping.Api", references);
        Assert.DoesNotContain("Shopping.Web", references);
    }

    [Fact]
    public void Contracts_do_not_reference_implementation_layers()
    {
        var references = GetReferencedAssemblyNames(typeof(ProductDto).Assembly);

        Assert.DoesNotContain("Shopping.Application", references);
        Assert.DoesNotContain("Shopping.Domain", references);
        Assert.DoesNotContain("Shopping.Infrastructure", references);
        Assert.DoesNotContain("Shopping.Api", references);
        Assert.DoesNotContain("Shopping.Web", references);
    }

    private static IReadOnlyCollection<string?> GetReferencedAssemblyNames(Assembly assembly)
    {
        return assembly.GetReferencedAssemblies()
                       .Select(reference => reference.Name)
                       .ToArray();
    }
}