# =============================================================================
# DEV APPLICATION INSIGHTS — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/app-insights/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable app-insights module to the dev environment.
#   Depends on both resource-group AND log-analytics — it reads the workspace ID
#   from the log-analytics module's state, not a hardcoded value.
#
# DEPLOYMENT ORDER (enforced by dependency blocks below):
#   resource-group → log-analytics → app-insights
#   You MUST deploy log-analytics before this module.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/app-insights
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
  source = "../../../modules/app-insights"
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
# DEPENDENCY: Log Analytics Workspace
#
# App Insights needs the workspace's RESOURCE ID (not the workspace_id GUID)
# to link itself to the workspace in workspace-based mode.
#
# We read the actual ID from the log-analytics module's state rather than
# hardcoding it. If the workspace is ever renamed or moved, this picks up
# the new value automatically after `terragrunt apply` on log-analytics.
# -----------------------------------------------------------------------------
dependency "log_analytics" {
  config_path = "../log-analytics"

  mock_outputs = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-log"
    workspace_id = "00000000-0000-0000-0000-000000000001"
    name         = "mock-log-antkart-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# INPUTS
#
# workspace_id = dependency.log_analytics.outputs.id:
#   This is the ARM resource ID of the Log Analytics workspace, not the GUID.
#   The variable name "workspace_id" in the module accepts the full resource ID.
#   The telemetry-only GUID (dependency.log_analytics.outputs.workspace_id) is
#   used by monitoring agents and alert rules, not by App Insights itself.
# -----------------------------------------------------------------------------
inputs = {
  name                = "appi-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name
  workspace_id        = dependency.log_analytics.outputs.id
  application_type    = "web"
  tags                = include.env.locals.common_tags
}
