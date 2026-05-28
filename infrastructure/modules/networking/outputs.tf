# =============================================================================
# NETWORKING MODULE — OUTPUTS
# File: infrastructure/modules/networking/outputs.tf
#
# These outputs are consumed by modules that depend on networking:
#   - AKS module:     needs aks_subnet_id to place node pools
#   - Private endpoints (CosmosDB, Key Vault, ACR): need pe_subnet_id
#   - Application Gateway (future): needs appgw_subnet_id
#   - Any module that needs to reference the VNet: vnet_id or vnet_name
# =============================================================================

output "vnet_id" {
  description = <<-EOT
    The full Azure Resource ID of the Virtual Network.
    Used for VNet peering, Private DNS Zone VNet links, and diagnostic settings.
    Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}
  EOT
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "The VNet name. Used when a child resource needs the VNet name rather than ID (e.g., azurerm_subnet references)."
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = <<-EOT
    Resource ID of the AKS node subnet.
    Pass this to the AKS module as the vnet_subnet_id for the default node pool.
    The AKS control plane will assign pod IPs from this subnet's address space.
  EOT
  value = azurerm_subnet.aks.id
}

output "pe_subnet_id" {
  description = <<-EOT
    Resource ID of the private endpoints subnet.
    Pass this to every azurerm_private_endpoint resource as its subnet_id.
    All private endpoints (CosmosDB, Key Vault, ACR, Service Bus) land here.
  EOT
  value = azurerm_subnet.pe.id
}

output "appgw_subnet_id" {
  description = <<-EOT
    Resource ID of the Application Gateway reserved subnet.
    Pass this to the azurerm_application_gateway resource when deploying AGW.
    Currently reserved — no resources deployed in this subnet yet.
  EOT
  value = azurerm_subnet.appgw.id
}

output "aks_nsg_id" {
  description = "Resource ID of the AKS subnet NSG. Used for diagnostic settings and additional rule management."
  value       = azurerm_network_security_group.aks.id
}

output "pe_nsg_id" {
  description = "Resource ID of the private endpoint subnet NSG."
  value       = azurerm_network_security_group.pe.id
}
