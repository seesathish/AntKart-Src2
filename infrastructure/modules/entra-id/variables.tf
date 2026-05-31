# =============================================================================
# ENTRA ID MODULE VARIABLES
# File: infrastructure/modules/entra-id/variables.tf
# =============================================================================

variable "api_app_name" {
  description = "Display name for the API app registration (resource server)"
  type        = string
}

variable "spa_app_name" {
  description = "Display name for the SPA/client app registration"
  type        = string
}

variable "environment" {
  description = "Environment name tag (dev, staging, prod)"
  type        = string
}

# ── Role GUIDs ────────────────────────────────────────────────────────────────
# App role IDs must be stable UUIDs. They are generated once and stored here
# as defaults so they remain constant across plan/apply runs.
# To regenerate: uuidgen (Linux/macOS) or [guid]::NewGuid() (PowerShell)

variable "user_role_id" {
  description = "GUID for the 'user' app role. Stable across applies — do not change after first deploy."
  type        = string
  default     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}

variable "admin_role_id" {
  description = "GUID for the 'admin' app role. Stable across applies — do not change after first deploy."
  type        = string
  default     = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
}

variable "access_as_user_scope_id" {
  description = "GUID for the access_as_user OAuth2 scope. Stable across applies."
  type        = string
  default     = "c3d4e5f6-a7b8-9012-cdef-123456789012"
}
