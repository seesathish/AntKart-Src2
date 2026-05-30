# =============================================================================
# DEV LOG ANALYTICS — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/log-analytics/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable log-analytics module to the dev environment.
#   This is the first module to deploy in Section 2 because Application Insights
#   depends on this workspace ID.
#
# DEPLOYMENT ORDER:
#   resource-group → log-analytics → app-insights
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/log-analytics
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
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
  source = "../../../modules/log-analytics"
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

inputs = {
  name                = "log-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = include.env.locals.common_tags
}
