# =============================================================================
# LOG ANALYTICS MODULE — OUTPUTS
# File: infrastructure/modules/log-analytics/outputs.tf
#
# Consumers of these outputs:
#   - App Insights module:   needs `id` to create workspace-based App Insights
#   - AKS module:            needs `id` to enable Container Insights add-on
#   - Diagnostic settings:   NSGs, Key Vault, ACR audit logs → `id` as destination
#   - Azure Monitor alerts:  `workspace_id` (the GUID) as the query data source
#   - primary_shared_key:    legacy agents that push data without managed identity
# =============================================================================

output "id" {
  description = <<-EOT
    Full Azure Resource ID of the Log Analytics Workspace.
    Pass this to Application Insights (workspace_id field) and to AKS Container
    Insights, and to any azurerm_monitor_diagnostic_setting resource.
    Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{name}
  EOT
  value = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "Workspace name. Used in KQL query sessions: az monitor log-analytics query --workspace <name>."
  value       = azurerm_log_analytics_workspace.this.name
}

output "workspace_id" {
  description = <<-EOT
    The GUID workspace identifier (different from the ARM resource ID).
    This is the identifier used in:
      - Azure Monitor alert rule query targets
      - Log Analytics query API calls
      - Some SDK integrations that accept a UUID rather than an ARM ID

    Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Note: different from `id` which is the full ARM resource path.
  EOT
  value = azurerm_log_analytics_workspace.this.workspace_id
}

output "primary_shared_key" {
  description = <<-EOT
    The primary shared key for workspace agent authentication.
    Used by the OMS agent and some legacy integrations that push data directly
    rather than using managed identity. Prefer managed identity ingestion where
    possible — it doesn't require this key at all.
    Marked sensitive — Terraform will not print this in plan or apply output.
  EOT
  value     = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive = true
}
