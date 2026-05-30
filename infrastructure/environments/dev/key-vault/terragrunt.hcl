# =============================================================================
# DEV KEY VAULT — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/key-vault/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable key-vault module to the dev environment.
#   The vault is created with Azure RBAC authorization and the deploying SP
#   is granted "Key Vault Secrets Officer" automatically by the module.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/key-vault
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# NAME CHECK BEFORE FIRST APPLY:
#   Key Vault names must be globally unique (3-24 chars).
#   "kv-antkart-dev" is 14 chars — within limits and likely unique.
#   If a previous vault with this name is in soft-deleted state, apply will fail.
#   Fix: az keyvault purge --name kv-antkart-dev --location eastus
#
# SOFT-DELETE REMINDER:
#   Destroying this module and re-applying with the same name requires either:
#   (a) Waiting 7 days for the soft-delete window to expire, OR
#   (b) Purging manually: az keyvault purge --name kv-antkart-dev --location eastus
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
  source = "../../../modules/key-vault"
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
# INPUTS
#
# tenant_id: the Entra ID tenant that owns the SP and AKS managed identity.
#   AntKart tenant: 4cacc56a-0d38-46c4-ba20-429d51d7b449
#   This is NOT a secret — it's a public identifier for the Azure AD directory.
#   The tenant ID is safe to hardcode here (it's equivalent to a domain name).
#
# soft_delete_retention_days = 7: minimum window, suitable for dev.
#   Increase to 90 for staging and prod.
# -----------------------------------------------------------------------------
inputs = {
  name                       = "kv-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location                   = include.env.locals.location
  resource_group_name        = dependency.resource_group.outputs.name
  tenant_id                  = "4cacc56a-0d38-46c4-ba20-429d51d7b449"
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  tags                       = include.env.locals.common_tags
}
