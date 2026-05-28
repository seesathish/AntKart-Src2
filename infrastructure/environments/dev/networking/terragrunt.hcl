# =============================================================================
# DEV NETWORKING — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/networking/terragrunt.hcl
#
# PURPOSE:
#   Wires the networking module to the dev environment. Demonstrates the
#   Terragrunt dependency pattern: this module reads the resource group's
#   name from state rather than hard-coding it.
#
# DEPLOYMENT ORDER:
#   You MUST deploy resource-group before networking. Terragrunt's dependency
#   block enforces this — it reads the RG name from the RG module's state file.
#   If you try to deploy networking first, Terragrunt will error:
#     "Error reading outputs from module..."
#
#   Correct order:
#     1. cd ../resource-group && terragrunt apply
#     2. cd ../networking    && terragrunt apply
#
#   Or from infrastructure/environments/dev/:
#     terragrunt run-all apply  ← Terragrunt figures out order from dependencies
# =============================================================================

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/networking"
}

# -----------------------------------------------------------------------------
# DEPENDENCY: Resource Group
#
# WHY declare a dependency?
#   The networking module needs resource_group_name as an input. We could
#   hard-code "rg-antkart-dev-eastus" in the inputs below, but that duplicates
#   information. If the RG name formula changes in env.hcl, we'd have to
#   update it here too — fragile.
#
#   Instead, we read the actual name from the resource-group module's OUTPUT
#   after it has been applied. This is the "outputs as contracts between modules"
#   pattern — the RG module owns its name, consumers just read it.
#
# config_path is relative to THIS file:
#   ../resource-group resolves to environments/dev/resource-group/
#   Terragrunt reads that folder's state file and exposes its outputs.
#
# mock_outputs:
#   During `terragrunt plan`, if the RG hasn't been applied yet, the dependency
#   outputs are unknown. mock_outputs provides fake values for plan-only runs
#   so you can validate the networking plan without deploying the RG first.
#   mock_outputs_allowed_terraform_commands limits mocks to safe commands only —
#   you can't accidentally apply with mock values.
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
# INPUTS — dev networking values
#
# CIDR PLAN for dev (network_octet = "0"):
#   VNet:        10.0.0.0/16   — 65,536 addresses total
#   AKS subnet:  10.0.0.0/22  — 1,024 addresses (nodes + Azure CNI pods)
#   PE subnet:   10.0.4.0/24  — 256 addresses  (private endpoints)
#   AppGW sub:   10.0.5.0/27  — 32 addresses   (reserved for future AGW)
#   Unallocated: 10.0.5.32 onwards — free for future subnets
#
# WHY string interpolation for address_space?
#   network_octet from env.hcl controls which /16 block each environment uses.
#   Interpolating it here means staging (octet=1) and prod (octet=2) get the
#   right ranges automatically when their terragrunt.hcl files are created.
# -----------------------------------------------------------------------------
inputs = {
  name                = "vnet-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name

  # The entire VNet address space. "10.0.0.0/16" for dev.
  address_space = ["10.${include.env.locals.network_octet}.0.0/16"]

  # Each subnet carved from the VNet address space.
  # All three must be non-overlapping subsets of address_space.
  subnet_prefixes = {
    aks   = "10.${include.env.locals.network_octet}.0.0/22"
    pe    = "10.${include.env.locals.network_octet}.4.0/24"
    appgw = "10.${include.env.locals.network_octet}.5.0/27"
  }

  tags = include.env.locals.common_tags
}
