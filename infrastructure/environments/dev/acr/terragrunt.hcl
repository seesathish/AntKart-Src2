# =============================================================================
# DEV ACR — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/acr/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable ACR module to the dev environment.
#   Reads shared values from env.hcl (location, tags, naming prefix) and the
#   resource group name from the resource-group module's remote state.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/acr
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# NAME CHECK BEFORE FIRST APPLY:
#   ACR names must be globally unique. Verify yours is available:
#     az acr check-name --name acrantkartdev
#   If unavailable, change the name suffix in the inputs block below.
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
  source = "../../../modules/acr"
}

# -----------------------------------------------------------------------------
# DEPENDENCY: Resource Group
#
# The ACR must live inside the resource group managed by the resource-group module.
# Rather than hard-coding "rg-antkart-dev-eastus", we read the actual name from
# the resource-group module's state output. If the naming formula ever changes
# in env.hcl, this dependency automatically picks up the new value.
# -----------------------------------------------------------------------------
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
# ACR naming rule: alphanumeric ONLY (no hyphens), globally unique, 5-50 chars.
# Pattern: acr<prefix><environment> → acrantkartdev
#
# If "acrantkartdev" is already taken by another Azure customer, append a suffix:
#   "acrantkartdev2026"   or   "acrantkartdev001"
# Verify before applying: az acr check-name --name acrantkartdev
# -----------------------------------------------------------------------------
inputs = {
  name                = "acr${include.env.locals.naming_prefix}${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name
  sku                 = "Basic"
  tags                = include.env.locals.common_tags
}
