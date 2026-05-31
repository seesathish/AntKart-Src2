# Entra ID Module

Creates Microsoft Entra ID (Azure AD) App Registrations to replace Keycloak as the identity provider for AntKart.

## Resources created

| Resource | Name | Purpose |
|----------|------|---------|
| `azuread_application` | `AntKart-API-<env>` | Protected resource — defines app roles and OAuth2 scopes |
| `azuread_service_principal` | (auto) | Service principal for the API app |
| `azuread_application` | `AntKart-SPA-<env>` | Client app — granted delegated access to the API |
| `azuread_service_principal` | (auto) | Service principal for the SPA |
| `azuread_service_principal_delegated_permission_grant` | (auto) | Pre-grants admin consent for SPA → API |

## App Roles

| Role | Value | Token claim |
|------|-------|-------------|
| User | `user` | `"roles": ["user"]` in the access token |
| Admin | `admin` | `"roles": ["admin"]` in the access token |

## Auth flow (how it replaces Keycloak)

```
Client → POST /api/auth/login (AK.UserIdentity)
       → ROPC grant → Entra token endpoint
       → Returns access_token (JWT with 'oid', 'roles', 'email' claims)

Client → Bearer token → API Gateway (Ocelot validates via AddEntraIdAuthentication)
       → Forwarded to downstream service (also validates independently)
       → GetUserId() reads 'oid' claim (stable Object ID, IDOR-safe)
       → RequireAuthorization("admin") checks 'roles' claim via ClaimTypes.Role
```

## Why `oid` instead of `sub`

In Entra ID, `sub` is pairwise — the same user gets a different `sub` value in each application. `oid` (Object ID) is stable across all apps in the tenant and never reused, making it the correct IDOR-safe user identifier.

## Deploy

```bash
cd infrastructure/environments/dev/entra-id
terragrunt init
terragrunt plan
terragrunt apply
```

## After apply — update appsettings

Copy the output values into all services' `appsettings.json`:

```json
"AzureAd": {
  "TenantId": "<tenant_id output>",
  "ClientId": "<api_client_id output>",
  "Audience": "<api_audience output>"
}
```

And in AK.UserIdentity only:
```json
"EntraId": {
  "ApiObjectId": "<api_object_id output>",
  "UserRoleId":  "<user_role_id output>"
}
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `api_app_name` | string | Display name for the API app registration |
| `spa_app_name` | string | Display name for the SPA app registration |
| `environment` | string | Environment tag (dev, staging, prod) |
| `user_role_id` | string | Stable GUID for the `user` app role |
| `admin_role_id` | string | Stable GUID for the `admin` app role |
| `access_as_user_scope_id` | string | Stable GUID for the `access_as_user` scope |

## Outputs

| Name | Description |
|------|-------------|
| `api_client_id` | API app client ID — `AzureAd:ClientId` in all services |
| `api_audience` | API Application ID URI — `AzureAd:Audience` in all services |
| `api_object_id` | API service principal Object ID — `EntraId:ApiObjectId` in UserIdentity |
| `user_role_id` | `user` app role GUID — `EntraId:UserRoleId` in UserIdentity |
| `admin_role_id` | `admin` app role GUID — for manual admin assignment |
| `tenant_id` | Tenant ID — verify against `AzureAd:TenantId` |
