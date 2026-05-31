# =============================================================================
# IDENTITY MODULE — OUTPUTS
# File: infrastructure/modules/identity/outputs.tf
#
# These outputs feed into the AKS Workload Identity configuration in Week 7.
#
# HOW OUTPUTS ARE USED IN WEEK 7:
#
#   client_id → annotated on the Kubernetes ServiceAccount:
#     kubectl annotate serviceaccount ak-products-sa \
#       azure.workload.identity/client-id=<client_id>
#     Or via Helm values / Terraform k8s provider.
#
#   principal_id → used to create additional role assignments if new cloud
#     resources are added later (e.g., Azure Storage, Cosmos new databases).
#
#   id → used in azurerm_federated_identity_credential.parent_id to link
#     the AKS OIDC issuer to this identity. See the federation step comment
#     in main.tf.
# =============================================================================

output "products_client_id" {
  description = "Client ID of the AK.Products managed identity. Annotate the k8s ServiceAccount with this in Week 7."
  value       = azurerm_user_assigned_identity.products.client_id
}

output "products_principal_id" {
  description = "Principal (object) ID of the AK.Products managed identity. Used for additional role assignments."
  value       = azurerm_user_assigned_identity.products.principal_id
}

output "products_identity_id" {
  description = "Full resource ID of the AK.Products managed identity. Used in azurerm_federated_identity_credential.parent_id in Week 7."
  value       = azurerm_user_assigned_identity.products.id
}

output "products_identity_name" {
  description = "Name of the AK.Products managed identity resource."
  value       = azurerm_user_assigned_identity.products.name
}
