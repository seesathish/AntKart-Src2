# =============================================================================
# APPLICATION INSIGHTS MODULE — MAIN
# File: infrastructure/modules/app-insights/main.tf
#
# PURPOSE:
#   Creates an Azure Application Insights resource — the APM (Application
#   Performance Monitoring) layer for AntKart microservices.
#
# WHAT APP INSIGHTS GIVES YOU:
#   - Distributed tracing: follow a single user request from the API Gateway
#     through AK.Products, AK.ShoppingCart, AK.Order, AK.Payments, and
#     AK.Notification — with timing at every hop
#   - Live Metrics: real-time request rate, failure rate, response time
#   - Exception tracking: full .NET stack traces with local variable capture
#   - Dependency tracking: slow PostgreSQL queries, Redis timeouts, gRPC failures
#   - Performance baselines: detect when response time regresses across a deploy
#
# WORKSPACE-BASED vs CLASSIC APP INSIGHTS:
#
#   Classic (standalone — DO NOT USE for new resources):
#     Each App Insights instance stores data in its own opaque backend.
#     You cannot write KQL queries that span multiple App Insights resources.
#     Microsoft announced Classic App Insights retirement on 29 February 2024.
#
#   Workspace-based (chosen here — required for all new resources):
#     App Insights stores all telemetry in a Log Analytics Workspace.
#     Benefits:
#       ∙ Cross-service correlation in one KQL query (all 8 microservices)
#       ∙ Combined dashboards with infrastructure data (AKS node metrics) in the
#         same workspace
#       ∙ Full KQL language for analysis (not limited to App Insights query UI)
#       ∙ Shared retention and cost management at the workspace level
#       ∙ Required: Azure will reject new App Insights resources without workspace_id
#
#   Enabling workspace mode: set workspace_id = <Log Analytics workspace resource ID>
#   The workspace_id comes from the log-analytics module output (dependency below).
#
# INSTRUMENTATION KEY vs CONNECTION STRING:
#   Older App Insights SDKs used the instrumentation_key (a bare GUID) to
#   authenticate telemetry submission. The modern approach is the connection string,
#   which bundles the key AND the ingestion endpoint:
#     InstrumentationKey=xxx;IngestionEndpoint=https://eastus-0.in.applicationinsights.azure.com/
#
#   The connection string is required for:
#     - OpenTelemetry with Azure Monitor exporter
#     - Azure Monitor .NET SDK 2.21+
#     - All new microservice integrations going forward
#
#   Both are exposed as outputs — instrumentation_key for any legacy SDK dependency,
#   connection_string as the primary value to use.
# =============================================================================

resource "azurerm_application_insights" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = var.application_type
  tags                = var.tags

  # workspace_id links this App Insights to the Log Analytics Workspace.
  # All telemetry data is stored there and queryable alongside infrastructure logs.
  # This is what makes this resource "workspace-based" — the required modern mode.
  workspace_id = var.workspace_id
}
