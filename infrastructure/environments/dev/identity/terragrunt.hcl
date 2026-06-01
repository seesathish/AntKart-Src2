# =============================================================================
# DEV IDENTITY — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/identity/terragrunt.hcl
#
# PURPOSE:
#   Wires the identity module to the dev environment.
#   Creates mi-ak-products-dev (User-Assigned Managed Identity for AK.Products)
#   and grants it:
#     - Key Vault Secrets User on kv-antkart-dev
#       → so the pod can read cosmos-connection-string at startup
#     - Azure Service Bus Data Owner on sb-antkart-dev
#       → so the pod can send and receive messages via MassTransit
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/identity
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# WEEK 7 FOLLOW-UP:
#   After the AKS cluster is provisioned, add a federated credential resource
#   to this module's environment wiring (or to the AKS module) linking:
#     - This managed identity (products_identity_id output)
#     - The AKS OIDC issuer URL
#     - The Kubernetes service account (namespace=ak-products, name=ak-products-sa)
#   See the Week 7 comment block in infrastructure/modules/identity/main.tf for
#   the exact Terraform resource definition.
#
# DEPENDENCIES:
#   resource-group → provides the resource group name + location
#   key-vault      → provides the Key Vault resource ID for role scoping
#   servicebus     → provides the Service Bus namespace resource ID for role scoping
#
# WHY ALL THREE DEPENDENCIES?
#   Role assignments must be scoped to a specific resource. The scope is the
#   resource ID — not its name. Reading the ID from the module's Terraform state
#   ensures that if a resource is ever renamed or recreated, this picks up the
#   new ID automatically without manual updates to this file.
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/identity"
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

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY: Key Vault
#
# The identity module grants Key Vault Secrets User to the managed identity.
# The role assignment's scope is the Key Vault's resource ID.
# The vault URI is NOT needed here — only the ID.
# ─────────────────────────────────────────────────────────────────────────────
dependency "key_vault" {
  config_path = "../key-vault"

  mock_outputs = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.KeyVault/vaults/mock-kv"
    name      = "mock-kv-antkart-dev"
    vault_uri = "https://mock-kv-antkart-dev.vault.azure.net/"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY: Service Bus
#
# The identity module grants Azure Service Bus Data Owner to the managed identity.
# The role assignment's scope is the Service Bus namespace resource ID.
# ─────────────────────────────────────────────────────────────────────────────
dependency "servicebus" {
  config_path = "../servicebus"

  mock_outputs = {
    namespace_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ServiceBus/namespaces/mock-sb"
    namespace_name = "mock-sb-antkart-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY: AKS — Workload Identity federation (added Week 7)
#
# The identity module creates a federated_identity_credential linking the
# AKS OIDC issuer to mi-ak-products-dev. Without the AKS module having been
# applied first, the issuer URL is unknown — the federation resource gates
# itself on `aks_oidc_issuer_url != null` so it skips creation cleanly.
#
# The skip_outputs / mock_outputs pattern lets you still `terragrunt plan`
# and `terragrunt apply` this module BEFORE AKS exists (matches the Week 5
# state). After AKS is applied, re-running terragrunt apply here picks up the
# real URL via outputs and creates the federation credential as a delta.
# ─────────────────────────────────────────────────────────────────────────────
dependency "aks" {
  config_path = "../aks"

  # Allow this dependency to be missing — the identity module skips federation
  # if the issuer URL is null. This is what lets the Week 5 ordering still work.
  skip_outputs = false

  mock_outputs = {
    name                       = "mock-aks-antkart-dev"
    oidc_issuer_url            = null
    node_resource_group        = "MC_mock-rg_mock-aks-antkart-dev_eastus"
    kubelet_identity_object_id = "00000000-0000-0000-0000-000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  # mi-ak-products-dev — naming: mi = managed identity, ak = AntKart prefix
  products_identity_name   = "mi-ak-products-${include.env.locals.environment}"
  location                 = include.env.locals.location
  resource_group_name      = dependency.resource_group.outputs.name
  key_vault_id             = dependency.key_vault.outputs.id
  service_bus_namespace_id = dependency.servicebus.outputs.namespace_id
  tags                     = include.env.locals.common_tags

  # Workload Identity federation. Until the AKS module is applied,
  # oidc_issuer_url will be null and the federation resource is skipped.
  # K8s namespace + ServiceAccount names match charts/values/products.yaml —
  # change here AND in the chart values together, or federation breaks silently.
  aks_oidc_issuer_url          = dependency.aks.outputs.oidc_issuer_url
  products_k8s_namespace       = "ak-products"
  products_k8s_service_account = "ak-products-sa"
}
