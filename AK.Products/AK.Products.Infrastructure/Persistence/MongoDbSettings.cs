namespace AK.Products.Infrastructure.Persistence;

// =============================================================================
// MONGO DB SETTINGS — DATABASE AND COLLECTION NAMES ONLY
//
// WHAT CHANGED IN WEEK 5:
//   ConnectionString was removed from this class. It was the local MongoDB URI
//   (mongodb://localhost:27017) — a plaintext secret embedded in appsettings.
//
//   The Cosmos DB connection string contains an account key and must never
//   appear in source control or config files. It is now fetched from Key Vault
//   at startup (see ServiceCollectionExtensions.AddInfrastructure) and passed
//   directly to MongoClient. This class only holds the non-secret database
//   coordinates (name and collection name).
//
// DATABASE NAME:
//   "antkart-products" is the Cosmos DB database provisioned by Terraform in Week 3.
//   In local MongoDB (Phase 1) this was "AKProductsDb". The rename reflects the
//   target cloud database name established when the Cosmos resource was created.
// =============================================================================
public sealed class MongoDbSettings
{
    public string DatabaseName { get; set; } = "antkart-products";
    public string ProductsCollection { get; set; } = "products";
}
