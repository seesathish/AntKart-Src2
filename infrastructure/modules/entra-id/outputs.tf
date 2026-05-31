# =============================================================================
# ENTRA ID MODULE OUTPUTS
# File: infrastructure/modules/entra-id/outputs.tf
#
# After `terragrunt apply`:
#   1. Copy api_client_id → appsettings.json "AzureAd:ClientId" in all services
#   2. Copy api_audience  → appsettings.json "AzureAd:Audience" in all services
#   3. Copy api_object_id → appsettings.json "EntraId:ApiObjectId" in UserIdentity
#   4. Copy user_role_id  → appsettings.json "EntraId:UserRoleId" in UserIdentity
#   5. Copy tenant_id     → confirm it matches the value already in appsettings.json
# =============================================================================

output "api_client_id" {
  description = "AntKart-API app registration client ID — use as AzureAd:ClientId in all services"
  value       = azuread_application.api.client_id
}

output "api_audience" {
  description = "AntKart-API Application ID URI — use as AzureAd:Audience in all services"
  value       = "api://${azuread_application.api.client_id}"
}

output "api_object_id" {
  description = "AntKart-API service principal Object ID — use as EntraId:ApiObjectId in UserIdentity"
  value       = azuread_service_principal.api.object_id
}

output "spa_client_id" {
  description = "AntKart-SPA app registration client ID — for future browser-based PKCE flows"
  value       = azuread_application.spa.client_id
}

output "user_role_id" {
  description = "GUID of the 'user' app role — use as EntraId:UserRoleId in UserIdentity"
  value       = var.user_role_id
}

output "admin_role_id" {
  description = "GUID of the 'admin' app role — for reference when assigning admin users"
  value       = var.admin_role_id
}

output "tenant_id" {
  description = "Entra tenant ID — confirm this matches AzureAd:TenantId in appsettings.json"
  value       = data.azuread_client_config.current.tenant_id
}
