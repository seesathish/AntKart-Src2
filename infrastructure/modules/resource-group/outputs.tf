# =============================================================================
# RESOURCE GROUP MODULE — OUTPUTS
# File: infrastructure/modules/resource-group/outputs.tf
#
# PURPOSE:
#   Outputs are the module's return values. Any module that declares a
#   Terragrunt dependency on this module can read these values via:
#     dependency.resource_group.outputs.<output_name>
#
# WHY expose id, name, AND location separately?
#   Different downstream modules need different things:
#     - networking, aks, acr → need resource_group_name (name)
#     - some resources accept resource_group_id for RBAC assignments (id)
#     - child resources that don't inherit location → need location
#   Exposing all three means consumers pick what they need without querying
#   the state file themselves.
#
# NAMING CONVENTION:
#   Outputs from this module are referenced as:
#     dependency.resource_group.outputs.name
#     dependency.resource_group.outputs.location
#     dependency.resource_group.outputs.id
# =============================================================================

output "id" {
  description = <<-EOT
    The full Azure Resource ID of the resource group.
    Format: /subscriptions/{subscription_id}/resourceGroups/{name}

    Used for: RBAC role assignments, Azure Policy scoping, ARM template references.
    Example consumer: AKS module assigning a Managed Identity role on the RG.
  EOT
  value = azurerm_resource_group.this.id
}

output "name" {
  description = <<-EOT
    The resource group name. This is what most child resources need:
      resource_group_name = dependency.resource_group.outputs.name

    Passing this as an output (rather than reconstructing the name string in
    every module) ensures consistency — there's one authoritative source.
  EOT
  value = azurerm_resource_group.this.name
}

output "location" {
  description = <<-EOT
    The Azure region the resource group was created in (e.g., "eastus").
    Child resources that need a location should reference this output rather
    than duplicating the region string — if the region ever changes, you
    update it in one place (env.hcl) and it flows through automatically.
  EOT
  value = azurerm_resource_group.this.location
}
