# =============================================================================
# DEV SERVICE BUS — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/servicebus/terragrunt.hcl
#
# PURPOSE:
#   Wires the servicebus module to the dev environment. Reads the resource group
#   name from the resource-group module and the Key Vault ID from the key-vault
#   module — no values are hardcoded.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/servicebus
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# NAME UNIQUENESS:
#   "sb-antkart-dev" must be globally unique across all Azure tenants.
#   Check before applying:
#     (name availability is not directly checkable via CLI — attempt apply;
#      "NamespaceAlreadyExists" error means the name is taken — add a suffix)
#   If taken, change the name input below (e.g., sb-antkart-dev-2026).
#
# COST NOTE — DESTROY WHEN IDLE:
#   Service Bus Standard costs ~$10/month even when idle. Unlike Cosmos DB
#   (stateful — has your data), Service Bus is pure messaging infrastructure.
#   Destroy it between dev sessions to avoid the base cost:
#
#     terragrunt destroy   # saves ~$10/month when not actively developing
#     terragrunt apply     # recreates in ~60 seconds when you need it
#
#   The connection string changes on recreate — Terraform updates the Key Vault
#   secret automatically on the next apply.
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
  source = "../../../modules/servicebus"
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
# The servicebus module writes the namespace connection string as a Key Vault
# secret named "servicebus-connection-string". It needs the Key Vault's
# resource ID to do so. Reading it from the key-vault module's state means
# if the vault is ever renamed, this picks up the new ID automatically.
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
  name                = "sb-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name
  sku                 = "Standard"
  key_vault_id        = dependency.key_vault.outputs.id
  tags                = include.env.locals.common_tags
}
