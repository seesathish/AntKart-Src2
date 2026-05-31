using MongoDB.Driver;
using Microsoft.Extensions.Options;

namespace AK.Products.Infrastructure.Persistence;

// =============================================================================
// MONGO DB CONTEXT — COSMOS DB (MONGODB API) EDITION
//
// WEEK 5 CHANGE: Production constructor now accepts a MongoClient singleton
// instead of constructing one internally from a connection string.
//
// WHY MongoClient IS INJECTED (not created here):
//   Cosmos DB enforces connection limits per account. Constructing a new
//   MongoClient each time MongoDbContext is created would open a new connection
//   pool — Cosmos throttles this aggressively and returns 429 errors. By
//   registering MongoClient as a singleton in DI (once per process lifetime)
//   and injecting it here, the entire application shares a single connection
//   pool. This is the Microsoft-recommended pattern for Cosmos MongoDB API.
//
// TWO CONSTRUCTORS:
//   Production: MongoDbContext(MongoClient, IOptions<MongoDbSettings>)
//     — used by the DI container. MongoClient carries the Cosmos connection
//       string retrieved from Key Vault at startup (never from config).
//
//   Test:       MongoDbContext(IMongoDatabase)
//     — used by unit tests. Tests inject a Mock<IMongoDatabase>, bypassing
//       the MongoClient, Key Vault, and Cosmos DB entirely. All 618 tests
//       remain isolated with no network dependency.
//
// INDEX CREATION:
//   Called only by the production constructor (real Cosmos connection).
//   Cosmos MongoDB API creates indexes idempotently — safe to run on every
//   startup. This ensures the collection has the required indexes even after
//   the database is wiped or recreated.
//
// COSMOS INDEXING NOTES:
//   Unlike native MongoDB (which indexes only _id by default), Cosmos DB
//   MongoDB API indexes ALL fields by default. Our explicit index calls
//   supplement this with a UNIQUE constraint on SKU and a text index.
//   The text index is the only Cosmos restriction to be aware of:
//   Cosmos allows exactly ONE text index per collection — we create one
//   compound text index (Name + Brand + Description), which satisfies this.
// =============================================================================
public sealed class MongoDbContext
{
    private readonly IMongoDatabase _database;

    // Production constructor — MongoClient is a singleton registered in DI by
    // ServiceCollectionExtensions. Its connection string was fetched from Key Vault.
    public MongoDbContext(MongoClient client, IOptions<MongoDbSettings> settings)
    {
        _database = client.GetDatabase(settings.Value.DatabaseName);
        CreateIndexes();
    }

    // Test constructor — injects a mocked IMongoDatabase directly.
    // Skips MongoClient, Key Vault, and real network entirely.
    public MongoDbContext(IMongoDatabase database)
    {
        _database = database;
    }

    public IMongoCollection<T> GetCollection<T>(string collectionName) =>
        _database.GetCollection<T>(collectionName);

    private void CreateIndexes()
    {
        var products = _database.GetCollection<Domain.Entities.Product>("products");

        // Enforce business rule: no two products can share the same SKU.
        // Cosmos MongoDB API: unique indexes are supported; this will throw
        // DuplicateKeyException if a seeder or API call tries to insert a duplicate SKU.
        var skuIndex = Builders<Domain.Entities.Product>.IndexKeys.Ascending(p => p.SKU);
        products.Indexes.CreateOne(new CreateIndexModel<Domain.Entities.Product>(
            skuIndex, new CreateIndexOptions { Unique = true, Name = "sku_unique" }));

        // Supporting index for GetByCategoryAsync and the category-filter query path.
        // RU note: without this index, a category filter would scan every document
        // in the collection — expensive at scale. The index makes it a targeted seek.
        var categoryIndex = Builders<Domain.Entities.Product>.IndexKeys.Ascending(p => p.CategoryName);
        products.Indexes.CreateOne(new CreateIndexModel<Domain.Entities.Product>(
            categoryIndex, new CreateIndexOptions { Name = "idx_category" }));

        // Supporting index for status-filtered list queries (e.g., Active products only).
        var statusIndex = Builders<Domain.Entities.Product>.IndexKeys.Ascending(p => p.Status);
        products.Indexes.CreateOne(new CreateIndexModel<Domain.Entities.Product>(
            statusIndex, new CreateIndexOptions { Name = "idx_status" }));

        // Compound text index for full-text search queries.
        // COSMOS CONSTRAINT: only ONE text index is allowed per collection.
        // This single index covers Name, Brand, and Description — do not create
        // additional text indexes or Cosmos will reject the second one at startup.
        // RU note: text searches are cross-partition by nature; each text search
        // query fans out across all logical partitions. For AntKart's scale this
        // is acceptable; at higher scale consider a dedicated search service.
        var textIndex = Builders<Domain.Entities.Product>.IndexKeys
            .Text(p => p.Name).Text(p => p.Brand).Text(p => p.Description);
        products.Indexes.CreateOne(new CreateIndexModel<Domain.Entities.Product>(
            textIndex, new CreateIndexOptions { Name = "text_search" }));
    }
}
