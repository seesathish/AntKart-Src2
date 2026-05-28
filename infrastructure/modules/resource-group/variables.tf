# =============================================================================
# RESOURCE GROUP MODULE — INPUT VARIABLES
# File: infrastructure/modules/resource-group/variables.tf
#
# Variables are the public API of a Terraform module. Whatever the caller
# (a terragrunt.hcl inputs block) passes in, these variables receive.
# Every variable has a description — not just "what type is it" but "what is
# it FOR and what format does it expect".
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The resource group name. Follow the Azure CAF (Cloud Adoption Framework)
    naming convention: rg-<workload>-<environment>-<region>
    Example: rg-antkart-dev-eastus

    Rules:
      - 1-90 characters
      - Letters, digits, underscores, hyphens, and periods allowed
      - Cannot end with a period
      - Must be unique within the subscription
  EOT
}

variable "location" {
  type        = string
  description = <<-EOT
    The Azure region where this resource group will be created.
    All resources inside the group must be deployed to the same region
    (or explicitly specify a different one — but that gets complicated).

    Common values: eastus, westeurope, centralindia, southindia, uksouth
    Full list: az account list-locations -o table
  EOT
}

variable "tags" {
  type        = map(string)
  description = <<-EOT
    A map of key-value pairs applied as Azure resource tags to the resource group.
    Tags propagate to all resources inside the group when you enable tag inheritance
    in Azure Policy (recommended for cost management).

    These are MERGED with the module's default tags (see main.tf locals).
    Caller-provided tags take precedence — you can override any default.

    Recommended tags at minimum: environment, project, managed_by, owner
    Example:
      tags = {
        environment = "dev"
        project     = "antkart"
        managed_by  = "terraform"
        owner       = "sathish"
      }
  EOT
  default     = {}
}
