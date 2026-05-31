# =============================================================================
# DEV ENTRA ID — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/entra-id/terragrunt.hcl
#
# PURPOSE:
#   Creates the Microsoft Entra ID App Registrations for the dev environment.
#   No dependency on any azurerm module — all resources are in Entra ID (Azure AD),
#   which is tenant-scoped, not subscription-scoped.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/entra-id
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# AFTER DEPLOY:
#   Copy the output values into all services' appsettings.json:
#     terragrunt output -json
#   See infrastructure/modules/entra-id/README.md for the mapping.
#
# GRANTING ADMIN ROLES TO YOUR USER:
#   After apply, assign yourself the "admin" role so you can test admin endpoints:
#     az ad user show --id seesathish@gmail.com --query id -o tsv   # get your OID
#     az rest --method POST \
#       --uri "https://graph.microsoft.com/v1.0/users/{yourOid}/appRoleAssignments" \
#       --body '{"principalId":"{yourOid}","resourceId":"{api_object_id}","appRoleId":"{admin_role_id}"}'
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/entra-id"
}

inputs = {
  api_app_name = "AntKart-API-${include.env.locals.environment}"
  spa_app_name = "AntKart-SPA-${include.env.locals.environment}"
  environment  = include.env.locals.environment

  # Role GUIDs — generated once, stable across applies.
  # Do NOT change these after the first apply — existing role assignments reference them.
  # user_role_id, admin_role_id, access_as_user_scope_id use module defaults.
}
