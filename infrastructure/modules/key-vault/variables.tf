# =============================================================================
# KEY VAULT MODULE — INPUT VARIABLES
# File: infrastructure/modules/key-vault/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Key Vault name.

    CONSTRAINTS:
      - 3 to 24 characters
      - Alphanumeric characters and hyphens only (no underscores, no dots)
      - Must start and end with a letter or digit
      - Must be GLOBALLY UNIQUE across all of Azure
      - Case-insensitive (Azure stores it lowercase internally)

    AntKart naming pattern: kv-<prefix>-<environment>
      dev:     kv-antkart-dev     (14 chars ✓)
      staging: kv-antkart-staging (18 chars ✓)
      prod:    kv-antkart-prod    (15 chars ✓)

    SOFT-DELETE NAMING CONFLICT:
      If a vault with this name was recently destroyed, Azure keeps it in a
      soft-deleted state for retention_days (default: 7 in dev). During this
      window, creating a new vault with the same name will fail:
        "A vault with the same name already exists in deleted state."
      Resolution options:
        1. Wait for the retention window to expire
        2. Purge the soft-deleted vault manually:
             az keyvault purge --name kv-antkart-dev --location eastus
        3. Use a different name (append a suffix like -2 or -v2)
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

variable "tenant_id" {
  type        = string
  description = <<-EOT
    The Azure Active Directory (Entra ID) Tenant ID.
    This links the vault to the correct directory for identity resolution.
    Every managed identity and Service Principal that accesses this vault
    must belong to this tenant.

    AntKart value: 4cacc56a-0d38-46c4-ba20-429d51d7b449
    Find yours: az account show --query tenantId -o tsv

    NEVER hardcode this in the module itself — it comes from the caller
    (environments/dev/key-vault/terragrunt.hcl inputs block) so staging
    and prod can use different tenants if required.
  EOT
}

variable "sku_name" {
  type        = string
  description = <<-EOT
    The Key Vault SKU. Controls whether keys are software-protected or HSM-protected.

    "standard" : Software-protected keys. Sufficient for secrets management.
                 Cost: ~$0/month base + ~$0.03 per 10,000 operations.
                 Secrets themselves have no per-secret storage fee.

    "premium"  : HSM-protected keys. Required for FIPS 140-2 Level 3 compliance
                 (PCI-DSS, government). Cost: ~$1/key/month + operations.
                 Not needed for AntKart Phase 2.

    Valid values: "standard", "premium"
  EOT
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be 'standard' or 'premium'."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  description = <<-EOT
    Days to retain soft-deleted vault objects before permanent deletion.
    Minimum: 7.  Maximum: 90.

    Dev:  7  — short window; dev secrets are not business-critical
    Prod: 90 — maximum; gives the longest possible recovery window

    During this window a deleted secret or vault can be recovered with:
      az keyvault secret recover --name <secret> --vault-name <vault>
      az keyvault recover --name <vault>
  EOT
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the Key Vault. Pass env.hcl common_tags."
  default     = {}
}
