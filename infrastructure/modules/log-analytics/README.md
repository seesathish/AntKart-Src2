# Module: log-analytics

Creates an Azure Log Analytics Workspace — the central telemetry store for the
AntKart platform. Every observability signal (traces, metrics, exceptions, container
logs, infrastructure events) flows into this workspace and is queryable with KQL.

## What this module does

1. Creates the workspace with the PerGB2018 pricing tier
2. Sets the data retention window (30 days for dev — the free minimum)
3. Exposes `id`, `name`, `workspace_id`, and `primary_shared_key` for consumers

## Why one workspace for everything?

A single shared workspace means:
- **Cross-service traces**: follow a request through the API Gateway, Products, Cart, Order, and Payments in one query
- **Single query endpoint**: all dashboards and alerts point to one resource
- **Volume discount**: the 5 GB/month free tier applies to the workspace total, not per resource

## Cost profile

| Usage | Cost |
|-------|------|
| First 5 GB/month | Free |
| Additional data | ~$2.30/GB |
| Retention beyond 30 days | ~$0.10/GB/day |
| Dev AntKart (estimated) | < 1 GB/month → **Free** |

## Deployment order

This module must be deployed **before** Application Insights and AKS Container Insights,
because both need this workspace ID.

```
resource-group → log-analytics → app-insights
                              → aks (Container Insights)
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Workspace name. Convention: `log-<project>-<environment>` |
| `location` | string | — | Azure region |
| `resource_group_name` | string | — | Resource group |
| `sku` | string | `"PerGB2018"` | Always PerGB2018 for new workspaces |
| `retention_in_days` | number | `30` | 30 (dev free minimum) to 730 |
| `tags` | map(string) | `{}` | Tags from env.hcl |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `id` | string | Full resource ID — pass to App Insights and AKS as workspace_id |
| `name` | string | Workspace name |
| `workspace_id` | string | GUID identifier (for API/alert rule targets) |
| `primary_shared_key` | string (sensitive) | Agent authentication key |
