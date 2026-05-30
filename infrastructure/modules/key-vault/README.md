# Module: key-vault

Creates an Azure Key Vault — the central secrets store for AntKart. All sensitive
configuration (Razorpay keys, database passwords, SMTP credentials, JWT secrets)
moves from `appsettings.json` files into this vault. AKS retrieves secrets at pod
startup via the Secrets Store CSI Driver.

## What this module does

1. Creates the Key Vault with Azure RBAC authorization (not legacy access policies)
2. Enables soft-delete (7 days dev / 90 days prod) and purge protection
3. Grants the deploying Service Principal the "Key Vault Secrets Officer" role
4. Protects the vault from accidental deletion with `prevent_destroy = true`
5. Exposes `id`, `name`, and `vault_uri` for downstream consumers

## RBAC vs Access Policies — why RBAC?

| Feature | Access Policies (legacy) | Azure RBAC (this module) |
|---------|--------------------------|--------------------------|
| Visible in standard IAM blade | No (separate blade) | Yes |
| Secret-level permission scope | No (vault only) | Yes |
| Conditional Access integration | No | Yes |
| Consistency with other Azure resources | No | Yes |

Setting `enable_rbac_authorization = true` activates the RBAC model. Access policies
are then ignored entirely — don't mix models.

## Soft-delete and the naming conflict

`purge_protection_enabled = true` means a destroyed vault stays in soft-deleted state
for `soft_delete_retention_days` before permanent deletion. Recreating with the same
name during this window will fail.

```bash
# List soft-deleted vaults
az keyvault list-deleted --resource-type vault

# Purge to free the name immediately
az keyvault purge --name kv-antkart-dev --location eastus
```

## Role assigned by this module

| Role | Principal | Scope |
|------|-----------|-------|
| Key Vault Secrets Officer | Terraform SP (deploying identity) | This vault |

AKS pods will get `Key Vault Secrets User` (read-only) — that assignment is created
in the AKS module when it is built (Week 3).

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Vault name. Alphanumeric + hyphens, 3-24 chars, globally unique |
| `location` | string | — | Azure region |
| `resource_group_name` | string | — | Resource group |
| `tenant_id` | string | — | Entra ID tenant ID |
| `sku_name` | string | `"standard"` | `standard` (software keys) or `premium` (HSM) |
| `soft_delete_retention_days` | number | `7` | 7 (dev) to 90 (prod) |
| `tags` | map(string) | `{}` | Tags from env.hcl |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Full resource ID — scope Key Vault Secrets User role for AKS here |
| `name` | Vault short name — use in `az keyvault secret` commands |
| `vault_uri` | HTTPS URI — use in SDK clients and CSI Driver config |
