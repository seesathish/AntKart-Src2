# =============================================================================
# IDENTITY MODULE — VARIABLES
# File: infrastructure/modules/identity/variables.tf
# =============================================================================

variable "products_identity_name" {
  description = "Name for the AK.Products user-assigned managed identity (e.g. mi-ak-products-dev)"
  type        = string
}

variable "location" {
  description = "Azure region where the managed identity is created"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the managed identities"
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault. Used to scope the Key Vault Secrets User role assignment."
  type        = string
}

variable "service_bus_namespace_id" {
  description = "Resource ID of the Service Bus namespace. Used to scope the Azure Service Bus Data Owner role assignment."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# WORKLOAD IDENTITY FEDERATION (added Week 7)
#
# These variables control whether the identity module creates a federated
# credential linking the AKS OIDC issuer to the Products managed identity.
#
# WHY THIS IS OPTIONAL:
#   The identity module was first applied in Week 5, BEFORE AKS existed —
#   aks_oidc_issuer_url was unknown then. The federation resource uses
#   `count = aks_oidc_issuer_url != null ? 1 : 0` so the module can still be
#   applied standalone before AKS exists. After AKS is applied in Week 7,
#   the identity module is re-applied with the URL populated and federation
#   is created on the second pass.
#
# ADDING MORE SERVICE IDENTITIES LATER (Weeks 8-9):
#   When AK.Order, AK.Payments, etc. need Workload Identity, copy the
#   Products pattern in main.tf — one identity resource + role assignments +
#   one federated credential per service. Each service's block is independent.
#   Add new variables here following the products_* pattern.
# -----------------------------------------------------------------------------
variable "aks_oidc_issuer_url" {
  description = <<-EOT
    OIDC issuer URL of the AKS cluster (e.g.
    https://eastus.oic.prod-aks.azure.com/<tenant>/<guid>/).
    Comes from the aks module's oidc_issuer_url output.

    Leave null to skip federation creation — useful when applying the identity
    module before AKS exists (Week 5 → Week 7 transition).
  EOT
  type    = string
  default = null
}

variable "products_k8s_namespace" {
  description = "Kubernetes namespace where the AK.Products pod runs. Combined with products_k8s_service_account to form the OIDC `subject` claim that the federated credential trusts."
  type        = string
  default     = "ak-products"
}

variable "products_k8s_service_account" {
  description = "Kubernetes ServiceAccount name used by AK.Products pods. Must match the serviceAccount.name set in charts/values/products.yaml."
  type        = string
  default     = "ak-products-sa"
}
