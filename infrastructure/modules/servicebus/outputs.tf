# =============================================================================
# SERVICE BUS MODULE — OUTPUTS
# File: infrastructure/modules/servicebus/outputs.tf
#
# Consumers:
#   - Key Vault secret:        connection_string written to KV in main.tf
#   - AK.Order (Week 5):       reads connection string from Key Vault to publish OrderCreated
#   - AK.Products (Week 5):    reads connection string from Key Vault to consume from products-subscription
#   - AK.Notification (Week 5): reads connection string from Key Vault to consume from notification-subscription
#   - Diagnostic settings:     `namespace_id` to scope monitoring
# =============================================================================

output "namespace_id" {
  description = "Full Azure Resource ID of the Service Bus namespace. Used to scope diagnostic settings and RBAC."
  value       = azurerm_servicebus_namespace.this.id
}

output "namespace_name" {
  description = "Namespace name (e.g., sb-antkart-dev). Used in az servicebus CLI commands."
  value       = azurerm_servicebus_namespace.this.name
}

output "queue_order_commands_id" {
  description = "Resource ID of the order-commands queue. Used to scope queue-specific RBAC (Azure Service Bus Data Sender/Receiver roles in Week 5)."
  value       = azurerm_servicebus_queue.order_commands.id
}

output "topic_integration_events_id" {
  description = "Resource ID of the integration-events topic. Used for diagnostic settings and topic-level RBAC."
  value       = azurerm_servicebus_topic.integration_events.id
}

output "connection_string" {
  description = <<-EOT
    The default primary connection string for the namespace (RootManageSharedAccessKey).
    Has Manage + Send + Listen permissions — broad by design for the interim period.
    Marked sensitive — Terraform will not print this value.

    Application services should read this from Key Vault
    (secret name: "servicebus-connection-string"), not from Terraform output.

    In Week 5, replace with Managed Identity authentication to eliminate SAS keys.
  EOT
  value     = azurerm_servicebus_namespace.this.default_primary_connection_string
  sensitive = true
}
