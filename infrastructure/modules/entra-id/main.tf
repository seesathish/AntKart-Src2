# =============================================================================
# ENTRA ID MODULE — App Registrations, App Roles, OAuth2 Scopes
# File: infrastructure/modules/entra-id/main.tf
#
# PURPOSE:
#   Replaces Keycloak with Microsoft Entra ID (Azure AD) as the identity provider.
#   Creates two App Registrations:
#     1. AntKart-API   — the protected resource; defines app roles and exposed scopes
#     2. AntKart-SPA   — the client app; granted delegated permission to call the API
#
# WHY TWO APP REGISTRATIONS?
#   Entra ID separates the resource (what you're protecting) from the client
#   (what calls the resource). The API app defines WHAT roles and scopes exist.
#   The SPA app is granted permission TO USE those scopes/roles. This separation
#   means you can add new client apps (mobile app, another service) by creating
#   a new app registration and granting it permission to the API app, without
#   touching the API app's security definition.
#
# APP ROLES vs SCOPES:
#   - App Roles: assigned to users/groups; appear in the 'roles' claim of the token.
#     Used for coarse-grained authorization: "is this user an admin?"
#   - Scopes (OAuth2 permissions): delegated permissions that users consent to.
#     Used for fine-grained API access: "can this app read my orders?"
#
# OUTPUTS:
#   api_client_id, spa_client_id      → update appsettings.json "AzureAd:ClientId"
#   api_object_id                     → update appsettings.json "EntraId:ApiObjectId"
#   user_role_id, admin_role_id       → update appsettings.json "EntraId:UserRoleId"
#   tenant_id                         → for reference (already known)
# =============================================================================

# Read the current Entra tenant metadata.
# Used to get tenant_id consistently without hardcoding it in multiple places.
data "azuread_client_config" "current" {}

# =============================================================================
# API APP REGISTRATION — AntKart-API
#
# This is the resource server: the thing being protected.
# All AntKart microservices validate Bearer tokens against this app's audience.
# =============================================================================

resource "azuread_application" "api" {
  display_name     = var.api_app_name
  identifier_uris  = ["api://${var.api_app_name}"]
  sign_in_audience = "AzureADMyOrg" # Single-tenant: only users from this tenant can log in

  # ── App Roles ──────────────────────────────────────────────────────────────
  # App roles appear as the 'roles' claim in access tokens when assigned to users.
  # The GUID for each role is generated once and must be stable — Terraform's
  # random_uuid would change on every apply, so we use deterministic values
  # provided as input variables (generated once, stored in variables.tf defaults).

  app_role {
    allowed_member_types = ["User"]
    description          = "Standard AntKart user — can browse products, place orders, manage their cart"
    display_name         = "User"
    id                   = var.user_role_id
    value                = "user"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "AntKart administrator — full platform access including user management"
    display_name         = "Admin"
    id                   = var.admin_role_id
    value                = "admin"
    enabled              = true
  }

  # ── Exposed Scopes (OAuth2 Permission Scopes) ──────────────────────────────
  # Scopes define what delegated operations a user can consent to.
  # 'access_as_user' is the single scope the SPA requests when a user logs in —
  # it signals "this app is acting on behalf of the user".

  api {
    requested_access_token_version = 2 # Use v2.0 tokens (shorter, standard claims)

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access AntKart API on behalf of the signed-in user"
      admin_consent_display_name = "Access AntKart API"
      user_consent_description   = "Allow this application to access AntKart API on your behalf"
      user_consent_display_name  = "Access AntKart API"
      enabled                    = true
      id                         = var.access_as_user_scope_id
      type                       = "User" # Requires individual user consent (not admin-only)
      value                      = "access_as_user"
    }
  }

  tags = ["AntKart", var.environment]
}

# Service principal for the API app — required for role assignments and for other
# apps to reference this resource in their required_resource_access blocks.
resource "azuread_service_principal" "api" {
  client_id                    = azuread_application.api.client_id
  app_role_assignment_required = false # Any user in the tenant can get a token; role assignment controls what they can do
}

# =============================================================================
# SPA / CLIENT APP REGISTRATION — AntKart-SPA
#
# This is the client: the thing calling the API.
# In a real deployment this would be the React/mobile frontend.
# For AntKart's current phase, AK.UserIdentity uses the API app's credentials
# (ROPC + client credentials) rather than a separate SPA app; the SPA app is
# created here for completeness and future browser-based auth flows.
# =============================================================================

resource "azuread_application" "spa" {
  display_name     = var.spa_app_name
  sign_in_audience = "AzureADMyOrg"

  # Request permission to use the API app's access_as_user scope.
  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = var.access_as_user_scope_id
      type = "Scope" # Delegated permission (user must consent)
    }
  }

  # Single-page application redirect URIs — localhost for dev; update for production.
  single_page_application {
    redirect_uris = ["http://localhost:3000/", "http://localhost:5173/"]
  }

  tags = ["AntKart", var.environment]
}

resource "azuread_service_principal" "spa" {
  client_id = azuread_application.spa.client_id
}

# =============================================================================
# GRANT ADMIN CONSENT for the SPA → API permission
#
# Without admin consent, every user would see a consent prompt on first login.
# Pre-granting consent avoids this for internal apps where an admin controls
# all user accounts.
# =============================================================================

resource "azuread_service_principal_delegated_permission_grant" "spa_to_api" {
  service_principal_object_id          = azuread_service_principal.spa.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = ["access_as_user"]
}
