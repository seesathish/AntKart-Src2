# =============================================================================
# COSMOS DB MODULE — OUTPUTS
# File: infrastructure/modules/cosmosdb/outputs.tf
#
# Consumers:
#   - AK.Products (Week 5):  reads connection string from Key Vault (not here)
#   - Key Vault secret:      connection_string is written to KV in main.tf
#   - AKS diagnostic config: needs `id` to scope monitoring settings
#   - Application code:      uses `endpoint` as the Cosmos DB URI for SDK auth
# =============================================================================

output "id" {
  description = "Full Azure Resource ID of the Cosmos DB account. Used to scope diagnostic settings and RBAC."
  value       = azurerm_cosmosdb_account.this.id
}

output "name" {
  description = "Account name (e.g., cosmos-antkart-dev). Used in az cosmosdb CLI commands."
  value       = azurerm_cosmosdb_account.this.name
}

output "endpoint" {
  description = <<-EOT
    The Cosmos DB account endpoint URI (e.g., https://cosmos-antkart-dev.documents.azure.com:443/).
    Used by applications that authenticate with RBAC (Managed Identity) rather than
    a connection string — the SDK needs the endpoint separately from the key in that flow.
    In Week 5 (Workload Identity), AK.Products will use this endpoint + managed identity,
    eliminating the need for the connection string secret entirely.
  EOT
  value = azurerm_cosmosdb_account.this.endpoint
}

output "database_name" {
  description = <<-EOT
    The MongoDB database name created inside this account (e.g., "antkart-products").
    AK.Products uses this as the MongoDB database name — kept identical to Phase 1
    so only the connection string changes during migration, not the code.
  EOT
  value = azurerm_cosmosdb_mongo_database.products.name
}

output "connection_string" {
  description = <<-EOT
    The primary MongoDB connection string for the Cosmos DB account.
    Marked sensitive — Terraform will not print this in plan or apply output.

    This output is provided for Terraform-to-Terraform consumption only.
    Application services should read the connection string from Key Vault
    (secret name: "cosmos-connection-string"), not from Terraform output.

    Format: mongodb://cosmos-antkart-dev:<key>@cosmos-antkart-dev.mongo.cosmos.azure.com:10255/?ssl=true&...

    Note: azurerm v4 removed connection_strings from azurerm_cosmosdb_account.
    The string is constructed in locals from primary_key + account name.
  EOT
  value     = local.mongo_connection_string
  sensitive = true
}
