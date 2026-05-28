# =============================================================================
# DEV ENVIRONMENT CONFIGURATION
# File: infrastructure/environments/dev/env.hcl
#
# PURPOSE:
#   Defines all dev-environment-specific values in one place. Every module
#   in environments/dev/ includes this file and reads its locals.
#
# HOW IT IS CONSUMED:
#   Each module-level terragrunt.hcl does:
#     include "env" {
#       path           = find_in_parent_folders("env.hcl")
#       expose         = true
#       merge_strategy = "no_merge"
#     }
#   Then references values as: include.env.locals.environment, etc.
#
#   The `expose = true` flag makes this file's locals accessible to the child.
#   The `merge_strategy = "no_merge"` means we're NOT merging inputs — only
#   reading locals. This keeps the env.hcl as pure configuration, with no
#   side-effects on the module's own inputs block.
#
# ENVIRONMENT ISOLATION STRATEGY:
#   dev, staging, and prod each have their own env.hcl with different values.
#   The module code (infrastructure/modules/) never changes between environments —
#   only the values in env.hcl differ. This is the "same code, different config"
#   principle, the same way appsettings.Development.json vs appsettings.Production.json
#   work in the AntKart .NET services.
# =============================================================================

locals {
  # The environment name. Used in resource names and tags.
  # Keep lowercase, no spaces — it forms part of Azure resource names.
  environment = "dev"

  # Azure region for all dev resources.
  # Matches the tfstate storage account region for locality.
  location = "eastus"

  # Short prefix for all resource names. Keep it short — Azure has name length
  # limits (e.g., storage accounts max 24 chars, key vaults max 24 chars).
  naming_prefix = "antkart"

  # Controls the second octet of the VNet address space.
  # dev=0 → 10.0.0.0/16, staging=1 → 10.1.0.0/16, prod=2 → 10.2.0.0/16
  # This ensures no CIDR overlap between environments — safe for future
  # VNet peering (e.g., for shared services) or VPN connectivity.
  network_octet = "0"

  # Tags applied to every resource in the dev environment.
  # These flow into every module via the inputs block.
  # WHY tag everything?
  #   1. Cost management: filter Azure Cost Analysis by environment or project
  #   2. Automation: policies can target or exempt resources by tag
  #   3. Accountability: the owner tag tells you who to contact about a resource
  common_tags = {
    environment = "dev"
    project     = "antkart"
    managed_by  = "terraform"
    owner       = "sathish"
  }
}
