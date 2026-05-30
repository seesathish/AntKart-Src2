# Module: app-insights

Creates an Azure Application Insights resource — the APM (Application Performance
Monitoring) layer for AntKart microservices. Linked to the Log Analytics Workspace
so all telemetry is queryable alongside infrastructure and container logs.

## What this module does

1. Creates a workspace-based Application Insights resource
2. Links it to the Log Analytics Workspace (`workspace_id`)
3. Exposes `id`, `name`, `instrumentation_key` (sensitive), and `connection_string` (sensitive)

## Workspace-based vs Classic — why it matters

| Mode | Data storage | Cross-service queries | Status |
|------|--------------|-----------------------|--------|
| Classic | Opaque per-resource store | ❌ Not possible | ⚠️ Retired Feb 2024 |
| Workspace-based | Log Analytics Workspace | ✅ Full KQL | ✅ Required for new resources |

Setting `workspace_id` activates workspace-based mode. This module requires
the log-analytics module to be deployed first.

## Connection string vs instrumentation key

Use the **connection string** for all new integrations:
```csharp
// Program.cs (OpenTelemetry)
builder.Services.AddOpenTelemetry()
    .UseAzureMonitor(options => {
        options.ConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
    });
```

The instrumentation key (bare GUID) is exposed for backwards-compatible SDKs only.

## Deployment dependency

```
log-analytics → app-insights   (workspace_id comes from log-analytics output)
```

Always deploy log-analytics before app-insights. Terragrunt's `dependency` block
in the environment wiring enforces this automatically.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Resource name. Convention: `appi-<project>-<environment>` |
| `location` | string | — | Azure region |
| `resource_group_name` | string | — | Resource group |
| `workspace_id` | string | — | Log Analytics resource ID from log-analytics module |
| `application_type` | string | `"web"` | Telemetry type — `"web"` for all AntKart services |
| `tags` | map(string) | `{}` | Tags from env.hcl |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `id` | string | Full resource ID |
| `name` | string | Resource name |
| `instrumentation_key` | string (sensitive) | GUID key — for legacy SDK compatibility |
| `connection_string` | string (sensitive) | Full connection string — use this in all services |
