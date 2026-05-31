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
