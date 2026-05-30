# =============================================================================
# ACR MODULE — INPUT VARIABLES
# File: infrastructure/modules/acr/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Azure Container Registry name.

    CONSTRAINTS (strictly enforced by Azure — plan will fail if violated):
      - 5 to 50 characters
      - Alphanumeric ONLY — absolutely NO hyphens, underscores, dots, or spaces
      - Must be GLOBALLY UNIQUE across all of Azure (like a domain name)
      - Lowercase only (the portal lowercases; be explicit in code)

    AntKart naming pattern: acr<prefix><environment>
      dev:     acrantkartdev     (13 chars ✓)
      staging: acrantkartsta    (14 chars ✓)
      prod:    acrantkartprd    (13 chars ✓)

    UNIQUENESS: If the default name is already taken by another Azure customer,
    append a short suffix. Examples:
      acrantkartdev2026    (year suffix — likely unique)
      acrantkartdev001     (numeric suffix)
    Check availability before applying:
      az acr check-name --name acrantkartdev

    The login server will be: <name>.azurecr.io (e.g., acrantkartdev.azurecr.io)
  EOT
}

variable "resource_group_name" {
  type        = string
  description = "The resource group to deploy the registry into. From dependency.resource_group.outputs.name."
}

variable "location" {
  type        = string
  description = "Azure region. Must match the resource group's region."
}

variable "sku" {
  type        = string
  description = <<-EOT
    The ACR service tier. Determines features, throughput limits, and monthly cost.

    "Basic"    ~$5/month  — dev: no private endpoints, no geo-replication; images private
    "Standard" ~$20/month — more throughput; still no private endpoints
    "Premium"  ~$50/month — private endpoints + geo-replication (AKS hardening phase)

    For dev, always use "Basic". The upgrade path to Premium is documented in main.tf.
    Changing SKU is a non-breaking in-place update (~) — no recreation required.
  EOT
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the registry resource. Pass env.hcl common_tags."
  default     = {}
}
