# =============================================================================
# DEV COSMOS DB — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/cosmosdb/terragrunt.hcl
#
# PURPOSE:
#   Wires the cosmosdb module to the dev environment. Reads the resource group
#   name from the resource-group module and the Key Vault ID from the key-vault
#   module — no values are hardcoded.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/cosmosdb
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# NAME UNIQUENESS:
#   "cosmos-antkart-dev" is globally unique in most cases, but verify first:
#     az cosmosdb check-name-exists --name cosmos-antkart-dev
#   If taken, change the name input below (e.g., cosmos-antkart-dev-2026).
#
# IMPORTANT — COST AND BILLING:
#   Serverless Cosmos DB has NO idle cost. You are only billed for RUs consumed.
#   Safe to leave running 24/7 during development.
# =============================================================================

# We pass "root.hcl" explicitly because find_in_parent_folders() defaults to
# searching for "terragrunt.hcl", but our root config is named "root.hcl"
# following the modern Terragrunt convention. See ADR-009.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/cosmosdb"
}

dependency "resource_group" {
  config_path = "../resource-group"

  mock_outputs = {
    name     = "mock-rg-antkart-dev-eastus"
    location = "eastus"
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# DEPENDENCY: Key Vault
#
# The cosmosdb module writes the connection string as a Key Vault secret.
# It needs the Key Vault's resource ID to do so. Reading it from the key-vault
# module's state means if the vault is ever renamed, this picks up the new ID.
# -----------------------------------------------------------------------------
dependency "key_vault" {
  config_path = "../key-vault"

  mock_outputs = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.KeyVault/vaults/mock-kv"
    name      = "mock-kv-antkart-dev"
    vault_uri = "https://mock-kv-antkart-dev.vault.azure.net/"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                = "cosmos-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name
  database_name       = "antkart-products"
  key_vault_id        = dependency.key_vault.outputs.id
  tags                = include.env.locals.common_tags
}
