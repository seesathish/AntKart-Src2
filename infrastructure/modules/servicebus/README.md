# Module: servicebus

Creates an Azure Service Bus namespace (Standard SKU) with the messaging primitives
for AntKart's event-driven architecture: a command queue, a pub/sub topic, and two
independent subscriptions representing the Products and Notification consumers.

## What this module does

1. Creates the Service Bus namespace (Standard SKU)
2. Creates the `order-commands` queue (point-to-point commands)
3. Creates the `integration-events` topic (pub/sub events)
4. Creates `products-subscription` and `notification-subscription` on the topic
5. Enables dead-lettering on message expiration for all consumers
6. Stores the connection string in Key Vault as `servicebus-connection-string`

## Queue vs Topic vs Subscription — the mental model

```
QUEUE (point-to-point):
  Publisher ──► [order-commands queue] ──► ONE consumer processes each message

TOPIC (pub/sub):
  Publisher ──► [integration-events topic]
                    ├──► [products-subscription]    ──► AK.Products
                    └──► [notification-subscription] ──► AK.Notification
  Each subscriber gets an INDEPENDENT copy of every message.
```

Use queues for **commands** (exactly one handler). Use topics for **events** (any number of handlers).

## Dead-letter queue — what and why

Every queue and subscription has an automatic dead-letter sub-queue. Messages land there when:
- The consumer fails to process after `max_delivery_count` attempts (default: 10)
- The message TTL expires without being processed

Dead-lettered messages are visible in the Azure portal's Service Bus Explorer. You can:
- Inspect the message body and properties to diagnose the failure
- Replay the message to the main queue/subscription after fixing the bug
- This is the "audit trail for failures" pattern — never silently drop messages

## SKU selection — why Standard and not Basic

| Feature | Basic | Standard (chosen) | Premium |
|---------|-------|-------------------|---------|
| Queues | ✅ | ✅ | ✅ |
| Topics + Subscriptions | ❌ | ✅ | ✅ |
| Dead-lettering | ❌ | ✅ | ✅ |
| VNet integration | ❌ | ❌ | ✅ |
| Base cost | ~$0 | ~$10/month | ~$670/month |

AntKart requires topics for its pub/sub fan-out. Basic is disqualified.

## Cost-saving tip: destroy when idle

Service Bus Standard charges ~$10/month even when no messages flow. Unlike Cosmos DB
(which has data), Service Bus is stateless messaging infrastructure — destroy it between
dev sessions to save the base cost:
```powershell
cd infrastructure/environments/dev/servicebus
terragrunt destroy   # saves ~$10/month when not actively developing
terragrunt apply     # recreates in ~60 seconds at start of next session
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Namespace name. Letters/digits/hyphens, 6-50 chars, globally unique |
| `location` | string | — | Azure region |
| `resource_group_name` | string | — | Resource group |
| `sku` | string | `"Standard"` | Basic / Standard / Premium |
| `key_vault_id` | string | — | Key Vault resource ID to store connection string |
| `tags` | map(string) | `{}` | Tags from env.hcl |

## Outputs

| Name | Description |
|------|-------------|
| `namespace_id` | Full resource ID |
| `namespace_name` | Namespace short name |
| `queue_order_commands_id` | Resource ID of the order-commands queue |
| `topic_integration_events_id` | Resource ID of the integration-events topic |
| `connection_string` | Primary connection string (sensitive — read from Key Vault in apps) |
