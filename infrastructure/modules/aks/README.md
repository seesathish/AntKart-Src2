# AKS Module

Provisions an Azure Kubernetes Service cluster with two node pools (system + user), Azure CNI, OIDC issuer, Workload Identity, and Container Insights wired to an existing Log Analytics workspace. Grants the cluster's kubelet identity AcrPull on the AntKart ACR.

## What this module creates

| Resource | Purpose |
|----------|---------|
| `azurerm_kubernetes_cluster.this` | The cluster control plane + system node pool (CoreDNS, metrics-server, Azure CNI, OMS agent) |
| `azurerm_kubernetes_cluster_node_pool.user` | App workload pool — independently scales 1–3 nodes |
| `azurerm_role_assignment.kubelet_acr_pull` | AcrPull on the ACR for the kubelet identity (image pulls) |

## Key design decisions (full rationale in ADR-015)

- **SKU tier:** Free in dev (no SLA), Standard in prod (99.95% SLA, $73/mo).
- **VM sizing:** `Standard_B2s` for both pools in dev (~$31/mo/node burstable). Prod overrides to a D-series for steady performance.
- **System pool taint:** `CriticalAddonsOnly=true:NoSchedule` (set via `only_critical_addons_enabled = true`). App pods can't land on the system pool by mistake.
- **Azure CNI** chosen over kubenet for direct pod IPs and clean private-endpoint connectivity to Cosmos / Service Bus.
- **OIDC issuer + Workload Identity enabled** — the entire reason this module exists in Phase 2C. Identity federation is configured in the identity module, not here.
- **Container Insights** wired to the existing Log Analytics workspace via `oms_agent` with managed-identity auth.

## Inputs

| Variable | Default | Source |
|----------|---------|--------|
| `name`, `location`, `resource_group_name`, `tags` | — | env wiring |
| `vnet_subnet_id` | — | `networking.aks_subnet_id` |
| `acr_id` | — | `acr.id` |
| `log_analytics_workspace_id` | — | `log_analytics.workspace_id` |
| `kubernetes_version` | null (AKS default) | env wiring |
| `system_node_vm_size` | `Standard_B2s` | env wiring |
| `system_node_min_count` / `max_count` | 1 / 2 | env wiring |
| `user_node_vm_size` | `Standard_B2s` | env wiring |
| `user_node_min_count` / `max_count` | 1 / 3 | env wiring |

## Outputs

| Output | Used by |
|--------|---------|
| `name`, `resource_group_name` | `az aks get-credentials` |
| `oidc_issuer_url` | identity module → federated credential `issuer` field |
| `node_resource_group` | Cost analysis filters |
| `kubelet_identity_object_id` | Future additional role grants |
| `kube_admin_config_raw`, `host` | CI/CD pipelines (sensitive) |

## Cost (dev sizing, running 24/7)

| Item | Monthly |
|------|---------|
| Control plane (Free tier) | $0 |
| 1× `Standard_B2s` system node | ~$31 |
| 1× `Standard_B2s` user node | ~$31 |
| Standard SKU Load Balancer | ~$18 |
| Container Insights ingestion (low) | $5–10 |
| Outbound IP + bandwidth | $3–5 |
| **Total** | **~$90–95** |

Destroy when not actively testing — see DevelopmentGuide §7.10.

## Deployment order

This module depends on:
1. `resource-group` (RG name + location)
2. `networking` (AKS subnet ID)
3. `acr` (registry ID for AcrPull)
4. `log-analytics` (workspace ID for Container Insights)

The identity module's federated credential depends on **this** module's `oidc_issuer_url` output — so the apply order across modules is:

```
resource-group → networking → acr → log-analytics → AKS → identity (re-apply for federation)
```
