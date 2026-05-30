# =============================================================================
# SERVICE BUS MODULE — INPUT VARIABLES
# File: infrastructure/modules/servicebus/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Service Bus namespace name.

    CONSTRAINTS:
      - 6 to 50 characters
      - Letters, digits, and hyphens only
      - Must start with a letter
      - Must be GLOBALLY UNIQUE across all of Azure
      - The namespace hostname will be: <name>.servicebus.windows.net

    AntKart naming pattern: sb-<prefix>-<environment>
      dev:     sb-antkart-dev     (13 chars ✓)
      staging: sb-antkart-staging (17 chars ✓)
      prod:    sb-antkart-prod    (14 chars ✓)

    If the name is taken, append a suffix: sb-antkart-dev-2026
    Check: the error "NamespaceAlreadyExists" during apply indicates a collision.
  EOT
}

variable "location" {
  type        = string
  description = "Azure region. Must match the resource group."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group from dependency.resource_group.outputs.name."
}

variable "sku" {
  type        = string
  description = <<-EOT
    The Service Bus namespace SKU. This is the most important variable to get right.

    "Basic"    ~$0/month base (pay-per-message):
      Queues ONLY. No topics, no subscriptions, no dead-lettering on topics.
      DISQUALIFIED for AntKart — pub/sub (topic + subscriptions) is required
      for the OrderCreated → Products + Notification fan-out pattern.

    "Standard" ~$10/month base (+ $0.10/million operations after first million free):
      Queues + Topics + Subscriptions + Dead-lettering.
      256 KB message size. No VNet integration. Correct for dev and staging.
      The ~$10/month base can be avoided by destroying when idle (see README).

    "Premium"  ~$670/month per messaging unit:
      Dedicated capacity, predictable latency, VNet integration, 100 MB messages.
      Required for production private networking. Far too expensive for dev.

    Valid values: "Basic", "Standard", "Premium"
  EOT
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "key_vault_id" {
  type        = string
  description = <<-EOT
    The resource ID of the Key Vault where the Service Bus connection string
    will be stored as a secret named "servicebus-connection-string".

    Pass: dependency.key_vault.outputs.id

    The deploying identity must have "Key Vault Secrets Officer" on this vault.
  EOT
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the namespace and all messaging entities. Pass env.hcl common_tags."
  default     = {}
}
