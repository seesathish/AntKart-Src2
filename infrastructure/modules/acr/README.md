# Module: acr

Creates an Azure Container Registry (ACR) — the private Docker registry where
AntKart microservice images are pushed by CI/CD and pulled by AKS at deployment.

## What this module does

1. Creates the ACR with the configured SKU (Basic for dev)
2. Disables admin credentials — access is RBAC-only
3. Exposes `id`, `name`, and `login_server` for downstream consumers (AKS, CI/CD)

## SKU and upgrade path

| SKU | Monthly cost | Private endpoints | Geo-replication | Use when |
|-----|-------------|------------------|-----------------|----------|
| Basic | ~$5 | No | No | Dev — always start here |
| Standard | ~$20 | No | No | Higher throughput needed |
| Premium | ~$50 | Yes | Yes | AKS private cluster hardening |

To upgrade: change `sku` in `environments/{env}/acr/terragrunt.hcl` and run
`terragrunt apply`. No module rework required — the change is in-place (`~`).

When upgrading to Premium, also:
1. Add an `azurerm_private_endpoint` resource on the `pe_subnet_id` from the networking module
2. Add a Private DNS Zone for `privatelink.azurecr.io` linked to the VNet

## Naming constraint — global uniqueness

ACR names must be globally unique across all of Azure (like a domain name).

```bash
# Check if a name is available before applying
az acr check-name --name acrantkartdev

# If taken, try a suffix
az acr check-name --name acrantkartdev2026
```

## Access model

This module creates the registry with `admin_enabled = false`. Access is granted via Azure RBAC:

| Role | Who gets it | Where assigned |
|------|-------------|----------------|
| AcrPull | AKS node managed identity | AKS module (during Week 3) |
| AcrPush | CI/CD Service Principal | GitHub Actions pipeline setup |
| Individual pull | Developers | `az acr login --name <name>` (uses personal az login) |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Registry name. Alphanumeric only, 5-50 chars, globally unique |
| `resource_group_name` | string | — | Resource group from RG module output |
| `location` | string | — | Azure region |
| `sku` | string | `"Basic"` | Service tier: Basic / Standard / Premium |
| `tags` | map(string) | `{}` | Tags from env.hcl common_tags |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Full resource ID — scope AcrPull/AcrPush role assignments here |
| `name` | Registry short name |
| `login_server` | FQDN for docker push/pull (e.g., `acrantkartdev.azurecr.io`) |
