# =============================================================================
# KEY VAULT MODULE — MAIN
# File: infrastructure/modules/key-vault/main.tf
#
# PURPOSE:
#   Creates an Azure Key Vault — the central secrets store for AntKart.
#   All sensitive configuration (Razorpay API keys, database passwords, SMTP
#   credentials, JWT signing keys) moves out of appsettings.json and
#   docker-compose files into this vault. AKS retrieves secrets at pod startup
#   via the Azure Key Vault Provider for Secrets Store CSI Driver.
#
# WHY RBAC AUTHORIZATION OVER ACCESS POLICIES?
#
#   Key Vault supports two authorization models. Choosing the right one now
#   saves a painful migration later.
#
#   ┌─────────────────────────────────────────────────────────────────────────┐
#   │ Access Policies (legacy)                                                │
#   │   - A custom, vault-specific permission system (NOT standard Azure RBAC)│
#   │   - Permissions live on the vault, not in the IAM blade                │
#   │   - Vault-level granularity only — cannot restrict to one specific secret│
#   │   - Not evaluated by Entra ID Conditional Access or PIM                 │
#   │   - Still supported but not recommended for new deployments             │
#   ├─────────────────────────────────────────────────────────────────────────┤
#   │ Azure RBAC (chosen here) — enable_rbac_authorization = true            │
#   │   - Uses standard Azure role assignments — visible in the IAM blade     │
#   │   - Supports secret-level scope: grant access to ONE specific secret    │
#   │   - Works with Conditional Access, PIM (privileged identity management) │
#   │   - Roles: Key Vault Secrets Officer (manage), Secrets User (read-only) │
#   │   - Consistent with all other Azure resource access control             │
#   │   - The approach in the Azure Landing Zone and modern Azure guidance     │
#   └─────────────────────────────────────────────────────────────────────────┘
#
#   IMPORTANT: Once enable_rbac_authorization = true is set, access policies are
#   completely ignored. Do not mix models. Choose RBAC and stay with it.
#
# SOFT-DELETE AND PURGE PROTECTION:
#
#   soft_delete_retention_days:
#     When a secret or the vault itself is deleted, Azure moves it to a
#     "soft-deleted" state rather than immediately destroying it. During the
#     retention window it can be recovered. Only after expiry is it gone.
#     In azurerm 4.x, soft-delete is always enabled; you control the window.
#
#   purge_protection_enabled = true:
#     Without this, a privileged identity can "purge" (permanently delete)
#     a soft-deleted vault immediately, bypassing the retention window.
#     With purge protection, NO ONE — not even the subscription owner —
#     can permanently delete a vault until the soft-delete window expires.
#     This defends against:
#       ∙ Ransomware: attacker can delete but cannot permanently destroy
#       ∙ Operational accidents: "I deleted the wrong vault" is recoverable
#
#   SIDE EFFECT: Purge protection means recreating a vault with the SAME NAME
#   requires waiting for the retention period to expire (or explicitly purging).
#   If you destroy this module and immediately re-apply, the create will fail:
#     "VaultAlreadyExists: A vault with the same name already exists in deleted state."
#   Fix: az keyvault purge --name kv-antkart-dev --location eastus
#   See Troubleshooting in DevelopmentGuide.md.
# =============================================================================

# Read the currently-authenticating Service Principal's object_id.
# Used below to grant the deploying SP the Secrets Officer role on this vault.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # The Entra ID tenant this vault belongs to. Must match the tenant of the
  # authenticating SP and the AKS managed identity that will read secrets.
  tenant_id = var.tenant_id

  # "standard" (software-protected keys) vs "premium" (HSM-protected keys).
  # Standard is sufficient for secrets management. Premium is for key material
  # requiring FIPS 140-2 Level 3 compliance (PCI-DSS, government workloads).
  sku_name = var.sku_name

  # Use Azure RBAC for authorization — see the module header for full explanation.
  # Once set to true, all access policy entries are ignored by Azure.
  # Renamed from enable_rbac_authorization in azurerm ~> 4.x (old name removed in v5).
  rbac_authorization_enabled = true

  # Soft-delete + purge protection: see module header for full explanation.
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = true

  lifecycle {
    # Key Vault holds secrets that every service depends on. Accidental deletion
    # would require waiting out the soft-delete window (7 days in dev) before
    # recreating with the same name. protect_destroy catches this at plan time.
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# RBAC ROLE ASSIGNMENT — Key Vault Secrets Officer for the deploying identity
#
# WHY this role assignment is necessary:
#   With enable_rbac_authorization = true, the vault has NO access by default.
#   Not even the subscription owner can read secrets without a role assignment.
#   The Terraform Service Principal needs "Key Vault Secrets Officer" to:
#     - Write secrets during infrastructure apply (e.g., store generated passwords)
#     - Read and update secrets from CI/CD pipelines
#     - Rotate secrets as part of operational runbooks
#
# LEAST PRIVILEGE:
#   Key Vault Secrets Officer → manage secrets ONLY (not keys, not certificates)
#   Key Vault Administrator   → full control (overkill — avoid)
#   Key Vault Secrets User    → read-only (for AKS pods — assigned in the AKS module)
#
# SCOPE: this specific vault only.
#   The role is NOT granted at the subscription level. If the SP needs access to
#   another vault (e.g., in staging), a separate role assignment is created there.
#
# principal_id = data.azurerm_client_config.current.object_id:
#   This resolves to the object ID of the identity running Terraform.
#   In CI/CD: the Service Principal.
#   Locally: your personal Entra ID identity (if you ran az login).
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
