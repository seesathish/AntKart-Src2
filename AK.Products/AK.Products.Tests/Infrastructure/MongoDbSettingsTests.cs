using AK.Products.Infrastructure.Persistence;
using FluentAssertions;

namespace AK.Products.Tests.Infrastructure;

public sealed class MongoDbSettingsTests
{
    // ConnectionString was removed from MongoDbSettings in Week 5.
    // The Cosmos connection string is now fetched from Key Vault at startup
    // (see ServiceCollectionExtensions.AddInfrastructure). It never appears
    // in settings, config files, or source control.

    [Fact]
    public void DefaultDatabaseName_ShouldBeAntkartProducts()
    {
        var settings = new MongoDbSettings();
        // "antkart-products" is the Cosmos DB database provisioned by Terraform in Week 3.
        // This replaces the Phase 1 local MongoDB database name "AKProductsDb".
        settings.DatabaseName.Should().Be("antkart-products");
    }

    [Fact]
    public void DefaultProductsCollection_ShouldBeProducts()
    {
        var settings = new MongoDbSettings();
        settings.ProductsCollection.Should().Be("products");
    }

    [Fact]
    public void Properties_CanBeSetAndRead()
    {
        var settings = new MongoDbSettings
        {
            DatabaseName = "TestDb",
            ProductsCollection = "TestCollection"
        };

        settings.DatabaseName.Should().Be("TestDb");
        settings.ProductsCollection.Should().Be("TestCollection");
    }

    [Fact]
    public void DefaultSecretName_ShouldBeCosmosConnectionString()
    {
        var cosmosSettings = new CosmosDbSettings();
        // Default secret name matches the Key Vault secret written by the
        // cosmosdb Terraform module in Week 3.
        cosmosSettings.SecretName.Should().Be("cosmos-connection-string");
    }

    [Fact]
    public void CosmosDbSettings_KeyVaultUri_DefaultsToEmpty()
    {
        var cosmosSettings = new CosmosDbSettings();
        // KeyVaultUri has no hardcoded default — it must come from appsettings.
        // An empty default ensures a clear startup error if config is missing,
        // rather than a cryptic "invalid URI" message later.
        cosmosSettings.KeyVaultUri.Should().BeEmpty();
    }

    [Fact]
    public void CosmosDbSettings_CanBeSetAndRead()
    {
        var cosmosSettings = new CosmosDbSettings
        {
            KeyVaultUri = "https://kv-antkart-dev.vault.azure.net/",
            SecretName = "cosmos-connection-string"
        };

        cosmosSettings.KeyVaultUri.Should().Be("https://kv-antkart-dev.vault.azure.net/");
        cosmosSettings.SecretName.Should().Be("cosmos-connection-string");
    }
}
