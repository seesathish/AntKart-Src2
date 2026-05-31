# Identity Module

Creates User-Assigned Managed Identities (UAMIs) for AntKart microservices and grants them the Azure RBAC roles they need to access cloud resources.

## Resources created

| Resource | Name | Purpose |
|----------|------|---------|
| `azurerm_user_assigned_identity` | `mi-ak-products-<env>` | Identity for the AK.Products pod in AKS |
| `azurerm_role_assignment` | — | Key Vault Secrets User on kv-antkart-dev |
| `azurerm_role_assignment` | — | Azure Service Bus Data Owner on sb-antkart-dev |

## Why User-Assigned (not System-Assigned)?

System-assigned identities are tied to the lifecycle of their host resource. AKS Workload Identity requires a **stable client ID** that exists before the pod starts. User-assigned identities are independent resources with a fixed client ID — the only supported identity type for Kubernetes Workload Identity federation.

## Workload Identity foundation (Week 5)

This module creates the identity and RBAC grants. The **federation step** (linking to AKS OIDC) is done in Week 7 when the AKS cluster is provisioned. The outputs of this module feed directly into the federated credential configuration:

- `products_client_id` → Kubernetes ServiceAccount annotation `azure.workload.identity/client-id`
- `products_identity_id` → `azurerm_federated_identity_credential.parent_id`

## Deploy

```bash
cd infrastructure/environments/dev/identity
terragrunt init
terragrunt plan
terragrunt apply
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `products_identity_name` | string | Name for the AK.Products managed identity |
| `location` | string | Azure region |
| `resource_group_name` | string | Resource group name |
| `key_vault_id` | string | Key Vault resource ID for KV Secrets User role |
| `service_bus_namespace_id` | string | Service Bus resource ID for SB Data Owner role |
| `tags` | map(string) | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `products_client_id` | UAMI client ID — annotate k8s ServiceAccount in Week 7 |
| `products_principal_id` | UAMI principal ID — use for additional role assignments |
| `products_identity_id` | Full resource ID — use in federated credential `parent_id` |
| `products_identity_name` | Resource name |
