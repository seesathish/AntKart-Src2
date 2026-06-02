# =============================================================================
# DEV AKS — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/aks/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable AKS module to the dev environment.
#   Reads the resource group, AKS subnet, ACR, and Log Analytics workspace IDs
#   from the upstream modules' state via dependency blocks.
#
# TO DEPLOY (~10-15 minutes):
#   cd infrastructure/environments/dev/aks
#   terragrunt init
#   terragrunt plan      # REVIEW node sizing carefully before applying
#   terragrunt apply
#
# AFTER APPLY:
#   1. Get kubectl credentials:
#        az aks get-credentials --resource-group rg-antkart-dev-eastus \
#                               --name aks-antkart-dev --overwrite-existing
#   2. Confirm nodes:        kubectl get nodes
#   3. Confirm system pool taint:
#        kubectl describe node | grep -A2 Taints
#   4. Apply the identity module again to add the Workload Identity federation
#      (it depends on this module's oidc_issuer_url output):
#        cd ../identity && terragrunt apply
#
# COST WARNING:
#   AKS is the largest single cost driver in AntKart dev (~$90/month if left
#   running). Destroy with `terragrunt destroy` when idle — see
#   DevelopmentGuide §7.10. The identity module and all other infra are kept
#   intact when AKS is destroyed; recreating takes 10-15 minutes.
# =============================================================================

# We pass "root.hcl" explicitly because find_in_parent_folders() defaults to
# "terragrunt.hcl", but our root config is named "root.hcl". See ADR-009.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/aks"
}

# -----------------------------------------------------------------------------
# DEPENDENCY: Resource Group
# Standard pattern — reads RG name from the resource-group module's state.
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
# DEPENDENCY: Networking
#
# AKS attaches both node pools to the aks_subnet_id. With Azure CNI, every pod
# consumes one IP from this subnet — the /22 sizing supports up to ~33 nodes
# worth of pods at the default 30 pods/node, which is enough for dev growth.
# -----------------------------------------------------------------------------
dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vnet_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name     = "mock-vnet"
    aks_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-aks-subnet"
    pe_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-pe-subnet"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# DEPENDENCY: ACR
#
# Needed for the AcrPull role assignment on the kubelet identity. Without this,
# pods can't pull antkart-base or service images and fail with ImagePullBackOff.
# -----------------------------------------------------------------------------
dependency "acr" {
  config_path = "../acr"

  mock_outputs = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerRegistry/registries/mockacr"
    name         = "mockacr"
    login_server = "mockacr.azurecr.io"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# DEPENDENCY: Log Analytics
#
# Container Insights ships container stdout/stderr, kube events, and node
# metrics into this workspace. Reusing the existing dev workspace means we
# don't pay for two ingestion pipelines.
# -----------------------------------------------------------------------------
dependency "log_analytics" {
  config_path = "../log-analytics"

  # NOTE: the log-analytics module exposes TWO outputs that look similar:
  #   - id            = full ARM resource ID /subscriptions/.../workspaces/<name>
  #   - workspace_id  = GUID only (used by query APIs)
  # AKS Container Insights needs `id` — passing the GUID fails plan time with
  # "parsing the Workspace ID: the number of segments didn't match".
  mock_outputs = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-la"
    workspace_id = "00000000-0000-0000-0000-000000000000"
    name         = "mock-la"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# INPUTS — dev cluster sizing
#
# Sizing decisions are deliberate and documented in ADR-015. The TL;DR:
#   - sku_tier: Free (no SLA) → ~$73/mo saved vs Standard. Acceptable for dev.
#   - vm_size:  Standard_B2s in both pools → ~$31/mo/node, burstable, enough
#               for stateless web services during dev work.
#   - min/max:  1-2 system, 1-3 user → covers 8-service dev fleet with headroom.
#
# Production wiring would override at minimum:
#   sku_tier (to "Standard"), system_node_vm_size, user_node_vm_size, max counts.
# -----------------------------------------------------------------------------
inputs = {
  name                = "aks-${include.env.locals.naming_prefix}-${include.env.locals.environment}"
  location            = include.env.locals.location
  resource_group_name = dependency.resource_group.outputs.name

  vnet_subnet_id = dependency.networking.outputs.aks_subnet_id
  acr_id         = dependency.acr.outputs.id

  # Use `.id` (full ARM resource ID), not `.workspace_id` (just the GUID).
  # AKS Container Insights needs the ARM ID; the GUID is for query APIs.
  log_analytics_workspace_id = dependency.log_analytics.outputs.id

  # All sizing falls back to module defaults (B2s, 1-2 system, 1-3 user).
  # Override here if dev needs more capacity for the Week 12-13 load test.
  # system_node_vm_size = "Standard_D2s_v5"
  # user_node_vm_size   = "Standard_D2s_v5"

  tags = include.env.locals.common_tags
}
