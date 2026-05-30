# =============================================================================
# LOG ANALYTICS MODULE — MAIN
# File: infrastructure/modules/log-analytics/main.tf
#
# PURPOSE:
#   Creates an Azure Log Analytics Workspace — the central telemetry data store
#   for the entire AntKart platform. Think of this as the "data lake" for all
#   observability signals:
#
#     Application Insights  → stores traces, metrics, exceptions here
#     AKS Container Insights → stores node/pod CPU, memory, restart data here
#     Azure Monitor          → stores Azure activity logs and alert history here
#     Diagnostic settings    → NSG flow logs, Key Vault audit logs here
#
# WHY ONE WORKSPACE FOR EVERYTHING?
#   You could create one workspace per service or per concern, but that fragments
#   your data and multiplies cost. One shared workspace means:
#
#     Cross-service correlation: trace a single user request from the API Gateway
#     through every microservice it touched — Products, ShoppingCart, Order,
#     Payments, Notification — in a single KQL query, in one UI.
#
#     Volume discount: the 5 GB/month free tier applies to the workspace total.
#     If you have 8 workspaces, each gets its own 5 GB "free" allotment but you
#     also pay for 8 workspaces × management overhead.
#
#     Single query endpoint: all Grafana dashboards, Azure Monitor alerts, and
#     Workbooks point to one workspace resource ID.
#
# COST PROFILE (PerGB2018 tier):
#   First 5 GB/month:  FREE
#   Additional data:   ~$2.30/GB/month
#   Dev AntKart (8 microservices, moderate traffic): expect < 1 GB/month → FREE
#   Retention beyond 30 days: ~$0.10/GB/day (billed once, as a "commitment")
#
# DEPLOYMENT ORDER:
#   This module MUST be deployed BEFORE Application Insights and BEFORE AKS
#   Container Insights are configured. Both depend on this workspace ID.
# =============================================================================

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  # PerGB2018 is the standard pay-per-use tier for new workspaces.
  # Legacy tiers (Free, Standalone, PerNode, Standard, Premium) are deprecated.
  # Always use PerGB2018 for any new workspace created after 2018.
  sku = var.sku

  # 30 days is the free retention minimum. Data older than this is automatically
  # deleted. Increase to 90-365 in prod for compliance (at extra cost).
  retention_in_days = var.retention_in_days

  tags = var.tags
}
