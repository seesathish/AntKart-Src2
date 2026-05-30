# =============================================================================
# LOG ANALYTICS MODULE — INPUT VARIABLES
# File: infrastructure/modules/log-analytics/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Log Analytics Workspace name.
    Convention: log-<project>-<environment>
      dev:     log-antkart-dev
      staging: log-antkart-staging
      prod:    log-antkart-prod

    Rules: 4-63 characters, alphanumeric and hyphens.
    Must be unique within the resource group (not globally required,
    but keep it unique to avoid confusion when querying across environments).
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

variable "sku" {
  type        = string
  description = <<-EOT
    The Log Analytics pricing tier.

    PerGB2018: the standard pay-per-GB tier. Correct for all new workspaces.
      - First 5 GB/month: FREE
      - Additional: ~$2.30/GB/month
      - Supports all workspace features (alerts, workbooks, KQL, etc.)

    Legacy tiers (Free, Standalone, PerNode, Standard, Premium) are deprecated
    for new workspaces. Microsoft no longer recommends them. Always use PerGB2018.
  EOT
  default     = "PerGB2018"
}

variable "retention_in_days" {
  type        = number
  description = <<-EOT
    How many days data is retained before automatic deletion.
    Minimum: 30 (free). Maximum: 730 (2 years, paid beyond 30 days).

    Cost for data beyond 30 days: ~$0.10/GB/day (charged once at ingestion,
    covers the full retention period).

    Dev:  30  — no compliance requirement; dev logs are not business records
    Prod: 90-365 depending on regulatory requirements (GDPR, SOC2, ISO 27001)
  EOT
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the workspace. Pass env.hcl common_tags."
  default     = {}
}
