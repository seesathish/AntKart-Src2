# =============================================================================
# EVENT GRID MODULE OUTPUTS
# File: infrastructure/modules/eventgrid/outputs.tf
# =============================================================================

output "topic_endpoint" {
  description = "Event Grid topic endpoint — AK.UserIdentity publishes events here"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "topic_id" {
  description = "Resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "topic_name" {
  description = "Name of the Event Grid custom topic"
  value       = azurerm_eventgrid_topic.main.name
}

# The topic access key is sensitive — it's used by AK.UserIdentity to publish events.
# In production this should be retrieved from Key Vault; for dev, use DefaultAzureCredential
# with Event Grid Data Sender role on the topic instead of a key.
output "topic_primary_key" {
  description = "Primary access key for the Event Grid topic (for local dev; prefer managed identity in AKS)"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}
