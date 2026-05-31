using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using AK.BuildingBlocks.Messaging;
using AK.BuildingBlocks.Resilience;
using AK.Products.Application.Consumers;
using AK.Products.Application.Interfaces;
using AK.Products.Infrastructure.Grpc;
using AK.Products.Infrastructure.Persistence;
using AK.Products.Infrastructure.Persistence.Repositories;
using AK.Products.Infrastructure.Seeders;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MongoDB.Driver;

namespace AK.Products.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    // =========================================================================
    // AddInfrastructure — WEEK 5: COSMOS DB (MONGODB API) + KEY VAULT PATTERN
    //
    // CONNECTION STRING FLOW:
    //   1. appsettings.json holds only non-secret references:
    //        CosmosDb:KeyVaultUri  — the vault's HTTPS endpoint (not a secret)
    //        CosmosDb:SecretName   — name of the secret (not a secret)
    //        MongoDbSettings:DatabaseName  — "antkart-products"
    //        MongoDbSettings:ProductsCollection — "products"
    //
    //   2. At startup, SecretClient fetches the Cosmos connection string from
    //      Key Vault using DefaultAzureCredential.
    //        Locally:  DefaultAzureCredential → AzureCliCredential (az login session)
    //        In AKS:   DefaultAzureCredential → WorkloadIdentityCredential (pod identity)
    //      Same code, different credential source — the identity concern is in the
    //      environment, not in the application.
    //
    //   3. The connection string is used to construct MongoClientSettings and then
    //      MongoClient. MongoClient is registered as a SINGLETON — one connection
    //      pool per process. This is critical for Cosmos: Cosmos throttles
    //      aggressive connection churn with 429 (TooManyRequests) errors.
    //
    //   4. MongoDbContext receives the MongoClient singleton via DI, gets the
    //      "antkart-products" database, and creates indexes at startup.
    //
    // WHY SYNCHRONOUS SECRET FETCH AT STARTUP:
    //   .GetSecret() is called synchronously (blocking) during DI registration,
    //   before the HTTP server accepts any requests. This is intentional:
    //   - If Key Vault is unreachable, the service fails immediately with a
    //     clear error rather than serving requests that will later fail on
    //     first DB access (fail-fast principle).
    //   - DI registration in .NET runs on the startup thread where async/await
    //     is awkward; the .GetAwaiter().GetResult() pattern is acceptable here
    //     because it runs once, at startup, not per-request.
    //
    // WHY THIS DIFFERS FROM SERVICE BUS AUTH:
    //   Service Bus supports Azure AD (token-based) auth natively — we pass
    //   DefaultAzureCredential directly to the Service Bus SDK. No key involved.
    //   Cosmos DB MongoDB API uses the MongoDB wire protocol, which authenticates
    //   with the account key embedded in the connection string. AAD auth for
    //   Cosmos MongoDB API is not supported in the MongoDB driver wire protocol.
    //   The Key Vault pattern is the pragmatic secure alternative: key stays in
    //   Key Vault, app fetches it once via its managed identity, never commits
    //   it anywhere.
    // =========================================================================
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        ProductClassMap.Register();

        // Bind the non-secret settings (database name, collection name).
        services.Configure<MongoDbSettings>(configuration.GetSection("MongoDbSettings"));
        services.Configure<CosmosDbSettings>(configuration.GetSection("CosmosDb"));

        // --- KEY VAULT SECRET FETCH ---
        // Retrieve the Cosmos DB connection string from Key Vault at startup.
        // This is the only place in the codebase that touches the actual secret.
        var cosmosSettings = configuration.GetSection("CosmosDb").Get<CosmosDbSettings>()
            ?? throw new InvalidOperationException("CosmosDb configuration section is missing.");

        var secretClient = new SecretClient(
            new Uri(cosmosSettings.KeyVaultUri),
            // DefaultAzureCredential tries credentials in order:
            //   Local dev: AzureCliCredential (your 'az login' session)
            //   AKS pod:   WorkloadIdentityCredential (pod's managed identity)
            // No code change needed between environments.
            new DefaultAzureCredential());

        var secret = secretClient.GetSecret(cosmosSettings.SecretName);
        var connectionString = secret.Value.Value;

        // --- MONGO CLIENT AS SINGLETON (CRITICAL FOR COSMOS) ---
        // MongoClientSettings.FromConnectionString parses the Cosmos connection
        // string (which includes ssl=true, replicaSet=globaldb, retrywrites=false,
        // and other Cosmos-specific parameters). These come from the Cosmos portal
        // / Terraform output — the driver honours them automatically.
        //
        // Additional setting: reduce ServerSelectionTimeout from the default 30s
        // so that a misconfigured connection fails fast rather than hanging.
        var mongoClientSettings = MongoClientSettings.FromConnectionString(connectionString);
        mongoClientSettings.ServerSelectionTimeout = TimeSpan.FromSeconds(10);

        // Register as singleton — the entire process shares one connection pool.
        // Never register MongoClient as Scoped or Transient with Cosmos.
        services.AddSingleton(new MongoClient(mongoClientSettings));

        // MongoDbContext is also singleton: it holds the IMongoDatabase reference
        // (which is thread-safe) and creates indexes once at startup.
        services.AddSingleton<MongoDbContext>();

        services.AddScoped<IProductRepository, ProductRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped<ProductSeeder>();

        services.Configure<DiscountGrpcSettings>(configuration.GetSection("DiscountGrpc"));
        services.AddHttpClient("discount-grpc", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(10);
        })
        .AddHttpResilienceWithCircuitBreaker(maxRetryAttempts: 3, failureRatio: 0.5, minimumThroughput: 3, breakDurationSeconds: 30);
        services.AddScoped<IDiscountGrpcClient, DiscountGrpcClient>();

        services.AddServiceBusMassTransit(configuration, "products", cfg =>
        {
            cfg.AddConsumer<ReserveStockConsumer>();
        });

        return services;
    }
}
