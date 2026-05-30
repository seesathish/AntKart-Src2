# =============================================================================
# APPLICATION INSIGHTS MODULE — INPUT VARIABLES
# File: infrastructure/modules/app-insights/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Application Insights resource name.
    Convention: appi-<project>-<environment>
      dev:     appi-antkart-dev
      staging: appi-antkart-staging
      prod:    appi-antkart-prod

    Rules: 1-260 characters, alphanumeric, hyphens, underscores, dots.
    Must be unique within the resource group (no global uniqueness requirement).
  EOT
}

variable "location" {
  type        = string
  description = "Azure region. Must match the resource group's region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group from dependency.resource_group.outputs.name."
}

variable "workspace_id" {
  type        = string
  description = <<-EOT
    The Log Analytics Workspace RESOURCE ID to link this App Insights to.
    This is what makes the resource "workspace-based" — the required modern mode.
    All telemetry flows to the workspace and is queryable with KQL.

    Pass: dependency.log_analytics.outputs.id  (the full ARM resource path)

    Note: this is the ARM resource ID (/subscriptions/.../workspaces/name),
    NOT the workspace_id GUID. They are different values from the same resource.

    Without this field, Terraform would attempt to create a deprecated "classic"
    App Insights resource — Azure now rejects those for new deployments.
  EOT
}

variable "application_type" {
  type        = string
  description = <<-EOT
    The application type. Affects how App Insights categorises telemetry data
    and which pre-built dashboards and analytics are available.

    "web"    : HTTP/REST services — correct for all AntKart microservices,
               including gRPC (the telemetry structure maps naturally to web)
    "other"  : Generic non-HTTP workloads (batch jobs, message consumers)
    "ios"    : Mobile — Apple
    "java"   : Java applications
    "Node.JS": Node.js services

    AntKart uses "web" for all 8 microservices.
  EOT
  default     = "web"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the App Insights resource. Pass env.hcl common_tags."
  default     = {}
}
