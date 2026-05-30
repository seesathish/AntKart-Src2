# =============================================================================
# ACR MODULE — OUTPUTS
# File: infrastructure/modules/acr/outputs.tf
#
# Consumers of these outputs:
#   - AKS module:          needs `id` to scope the AcrPull role assignment
#                          needs `login_server` to configure kubelet's image source
#   - GitHub Actions CI/CD: needs `login_server` to tag images before push
#   - Developers (manual): need `name` for `az acr login --name <name>`
# =============================================================================

output "id" {
  description = <<-EOT
    Full Azure Resource ID of the container registry.
    Used to scope RBAC role assignments:
      AKS managed identity → AcrPull role → this registry ID
    Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ContainerRegistry/registries/{name}
  EOT
  value = azurerm_container_registry.this.id
}

output "name" {
  description = <<-EOT
    Registry name (e.g., "acrantkartdev").
    Used in:
      az acr login --name acrantkartdev
      az acr repository list --name acrantkartdev
  EOT
  value = azurerm_container_registry.this.name
}

output "login_server" {
  description = <<-EOT
    The registry's fully qualified login server URL (e.g., acrantkartdev.azurecr.io).
    This is the hostname prefix used for every image reference:
      docker push  acrantkartdev.azurecr.io/antkart-products:v1.0.0
      image:       acrantkartdev.azurecr.io/antkart-products:v1.0.0   (in Kubernetes manifests)
      az acr login --name acrantkartdev
  EOT
  value = azurerm_container_registry.this.login_server
}
