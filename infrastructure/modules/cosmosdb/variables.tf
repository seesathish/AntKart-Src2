# =============================================================================
# COSMOS DB MODULE — INPUT VARIABLES
# File: infrastructure/modules/cosmosdb/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Cosmos DB account name.

    CONSTRAINTS:
      - 3 to 44 characters
      - Lowercase letters, digits, and hyphens only
      - Must start with a lowercase letter or digit
      - Must be GLOBALLY UNIQUE across all of Azure

    AntKart naming pattern: cosmos-<prefix>-<environment>
      dev:     cosmos-antkart-dev     (18 chars ✓)
      staging: cosmos-antkart-staging (22 chars ✓)
      prod:    cosmos-antkart-prod    (19 chars ✓)

    UNIQUENESS: The DNS hostname will be <name>.documents.azure.com.
    If the name is taken, append a suffix: cosmos-antkart-dev-2026
    Check availability: az cosmosdb check-name-exists --name cosmos-antkart-dev
  EOT
}

variable "location" {
  type        = string
  description = "Azure region. Must match the resource group's region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group from dependency.resource_group.outputs.name."
}

variable "database_name" {
  type        = string
  description = <<-EOT
    The MongoDB database name to create inside the Cosmos DB account.
    AntKart value: "antkart-products" — matches the AKProductsDb used by AK.Products in Phase 1.
    Keeping the name consistent means only the connection string needs to change
    when migrating from local MongoDB to Cosmos DB in Week 5.
  EOT
  default     = "antkart-products"
}

variable "key_vault_id" {
  type        = string
  description = <<-EOT
    The resource ID of the Key Vault where the Cosmos DB connection string
    will be stored as a secret named "cosmos-connection-string".

    Pass: dependency.key_vault.outputs.id

    The deploying identity must have "Key Vault Secrets Officer" on this vault
    (granted by the key-vault module in Week 2) to write secrets during apply.
  EOT
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the Cosmos DB account and database. Pass env.hcl common_tags."
  default     = {}
}
