namespace AK.Products.Infrastructure.Persistence;

// =============================================================================
// COSMOS DB SETTINGS — NON-SECRET REFERENCES ONLY
//
// WHY THESE ARE NOT SECRETS:
//   KeyVaultUri  — the public HTTPS endpoint of the Key Vault. Knowing it
//                  gives you nothing without a valid Azure identity.
//   SecretName   — the name of the secret inside the vault. Also not sensitive.
//
// The actual connection string (which contains the Cosmos account key) is fetched
// at startup by SecretClient using DefaultAzureCredential. It never appears in
// any config file, environment variable, or source control.
//
// HOW THIS DIFFERS FROM SERVICE BUS AUTH:
//   Service Bus supports Azure AD token auth natively (no key in the connection
//   string). So for Service Bus we only need the namespace FQDN and use
//   DefaultAzureCredential directly for all operations.
//
//   Cosmos DB MongoDB API uses the MongoDB wire protocol, which authenticates
//   with a username/password embedded in the connection string. Azure AD /
//   Entra ID token auth for Cosmos MongoDB API is very limited (only supported
//   in specific SDK flows, not the MongoDB driver wire protocol). The pragmatic
//   and secure pattern for Cosmos MongoDB API is therefore:
//     1. Store the account key-based connection string in Key Vault.
//     2. Read it from Key Vault at startup using DefaultAzureCredential.
//     3. Use the connection string for MongoDB.Driver — still no secret in config.
//
//   In AKS (Week 7): the pod's Workload Identity (Managed Identity) will have
//   Key Vault Secrets User role. DefaultAzureCredential picks it up automatically.
//   Zero code change between local dev and production.
// =============================================================================
public sealed class CosmosDbSettings
{
    public string KeyVaultUri { get; set; } = string.Empty;

    // Name of the secret in Key Vault that contains the Cosmos MongoDB connection string.
    // The secret was written by the cosmosdb Terraform module in Week 3.
    public string SecretName { get; set; } = "cosmos-connection-string";
}
