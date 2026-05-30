# =============================================================================
# APPLICATION INSIGHTS MODULE — OUTPUTS
# File: infrastructure/modules/app-insights/outputs.tf
#
# Consumers of these outputs:
#   - Key Vault (Week 3):       connection_string stored as a secret
#   - AKS pod manifests (Week 3): APPLICATIONINSIGHTS_CONNECTION_STRING env var
#   - Azure Monitor workbooks:  id for scoping
#   - Terraform-managed alerts: id as the telemetry source
# =============================================================================

output "id" {
  description = "Full Azure Resource ID of the Application Insights resource."
  value       = azurerm_application_insights.this.id
}

output "name" {
  description = "Resource name (e.g., appi-antkart-dev). Used in portal navigation and az monitor commands."
  value       = azurerm_application_insights.this.name
}

output "instrumentation_key" {
  description = <<-EOT
    The instrumentation key (GUID format). Used by older SDK versions.
    Prefer connection_string for all new integrations — it bundles the key
    with the ingestion endpoint and is required by OpenTelemetry exporters.
    Marked sensitive — do not print in logs or CI/CD output.
  EOT
  value     = azurerm_application_insights.this.instrumentation_key
  sensitive = true
}

output "connection_string" {
  description = <<-EOT
    The Application Insights connection string. This is the single value to
    inject into every microservice as:
      APPLICATIONINSIGHTS_CONNECTION_STRING=<value>

    It bundles the instrumentation key and the regional ingestion endpoint:
      InstrumentationKey=xxx;IngestionEndpoint=https://eastus-0.in.applicationinsights.azure.com/

    Use with:
      - Azure Monitor .NET SDK (Microsoft.ApplicationInsights 2.21+)
      - OpenTelemetry Azure Monitor Exporter (Azure.Monitor.OpenTelemetry.Exporter)
      - Azure Functions runtime

    This value will be stored in Key Vault (as a secret named "AppInsightsConnectionString")
    and mounted into AKS pods via the Secrets Store CSI Driver in Week 3.
    Marked sensitive — Terraform will not print this value in plan or apply output.
  EOT
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}
