# =============================================================================
# SERVICE BUS MODULE — MAIN
# File: infrastructure/modules/servicebus/main.tf
#
# PURPOSE:
#   Creates an Azure Service Bus namespace with the messaging entities that
#   support AntKart's event-driven microservice architecture: a command queue
#   for point-to-point messaging and a topic with subscriptions for pub/sub.
#
# WHY AZURE SERVICE BUS INSTEAD OF KEEPING RABBITMQ?
#   Phase 1 uses RabbitMQ running in a Docker container — correct for local dev.
#   For Azure deployment:
#     - Managed service: no VM, no ops, no broker cluster to maintain
#     - Native integration with Azure Monitor, Key Vault, and Managed Identity
#     - 99.9% (Standard) / 99.95% (Premium) SLA — much higher than a single
#       self-managed RabbitMQ container
#     - MassTransit (already used in AntKart) has first-class Service Bus support:
#       replacing RabbitMQ is a transport swap, not an architectural change
#
# SKU COMPARISON — WHY STANDARD?
#
#   Basic    (~$0/month base, pay-per-message):
#     - Queues ONLY. No topics, no subscriptions, no pub/sub.
#     - AntKart's event-driven flow (OrderCreated → Products + Notification) requires
#       topics. Basic SKU is disqualified. Never use Basic for AntKart.
#
#   Standard (~$10/month base):
#     - Queues + Topics + Subscriptions — everything AntKart needs
#     - 256 KB message size limit
#     - No VNet integration (traffic goes over public internet with TLS + auth)
#     - Correct for dev and staging
#
#   Premium  (~$670/month per messaging unit):
#     - Dedicated capacity: predictable latency, no noisy-neighbour effect
#     - VNet integration: namespace accessible only from private VNet
#     - 100 MB message size limit
#     - Required for production when low-latency SLA or network isolation is needed
#     - Way too expensive for dev
#
# DESTROY-WHEN-IDLE STRATEGY:
#   Unlike Cosmos DB (has data), Service Bus is pure messaging infrastructure.
#   Messages in transit are transient — if the namespace is destroyed during
#   development, no permanent data is lost. The ~$10/month Standard base cost
#   can be saved by running: cd environments/dev/servicebus && terragrunt destroy
#   Recreate when starting a development session that needs messaging.
#   For this reason, no prevent_destroy is set on this module.
#
# PRIVATE ENDPOINTS (future hardening):
#   Premium SKU + VNet integration makes the namespace private. Steps:
#     1. Upgrade to sku = "Premium"
#     2. Add azurerm_private_endpoint on pe_subnet_id from networking module
#     3. Set a network rule to deny public access
#   No module changes are needed — these are additive resources.
# =============================================================================

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# SERVICE BUS NAMESPACE
#
# The namespace is the top-level container — like a hostname for all messaging
# entities within it. The connection string authenticates to the namespace,
# and then the application specifies which queue or topic to use.
# -----------------------------------------------------------------------------
resource "azurerm_servicebus_namespace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags

  # local_auth_enabled controls whether Shared Access Signature (SAS) keys are
  # accepted. We use SAS for now (connection string auth) — kept true.
  # When migrating to Managed Identity in Week 5, set this to false to disable
  # SAS entirely and enforce RBAC-only access.
  local_auth_enabled = true
}

# -----------------------------------------------------------------------------
# QUEUE: order-commands
#
# WHY A QUEUE (not a topic)?
#   A queue implements point-to-point messaging: exactly one consumer processes
#   each message. Commands ("create this order", "process this payment") should
#   be handled by exactly one service instance — a queue is the right primitive.
#
# CONTRAST WITH TOPIC (pub/sub below):
#   Commands go to queues (one consumer).
#   Events go to topics (many consumers, each gets a copy).
#
# dead_lettering_on_message_expiration:
#   When a message's lock_duration expires (nobody processed it), Azure moves it
#   to the dead-letter sub-queue rather than silently dropping it. This creates
#   an audit trail of unprocessed messages that you can inspect and replay.
#   Always enable this in production — silent drops are the worst kind of bug.
#
# max_delivery_count = 10:
#   After 10 failed delivery attempts (consumer crashes, throws an exception),
#   Azure moves the message to the dead-letter queue automatically. This prevents
#   a "poison message" from blocking the queue forever.
# -----------------------------------------------------------------------------
resource "azurerm_servicebus_queue" "order_commands" {
  name         = "order-commands"
  namespace_id = azurerm_servicebus_namespace.this.id

  # After 10 failed delivery attempts, move to dead-letter queue.
  max_delivery_count = 10

  # Move to dead-letter queue when the message TTL expires without being processed.
  dead_lettering_on_message_expiration = true

  # How long a consumer has to process and settle a message before it becomes
  # visible again for redelivery. PT1M = 1 minute (ISO 8601 duration format).
  lock_duration = "PT1M"
}

# -----------------------------------------------------------------------------
# TOPIC: integration-events
#
# WHY A TOPIC (not a queue)?
#   A topic implements publish-subscribe: one publisher, many independent subscribers.
#   When an order is created, BOTH the Products service (to reserve stock) AND the
#   Notification service (to send confirmation email) need to react. With a queue,
#   only one of them would receive the message. With a topic + subscriptions, EACH
#   subscriber gets its own independent copy of every message.
#
# This is the core of AntKart's event-driven architecture: services publish events
#   without knowing who consumes them. New consumers are added by creating a new
#   subscription — the publisher doesn't change.
#
# MassTransit maps to Service Bus topics automatically when configured with the
#   Service Bus transport. A MassTransit consumer class → a subscription filter.
# -----------------------------------------------------------------------------
resource "azurerm_servicebus_topic" "integration_events" {
  name         = "integration-events"
  namespace_id = azurerm_servicebus_namespace.this.id

  # How long a message is retained in the topic if no subscription reads it.
  # P1D = 1 day. Increase for prod to ensure no message is lost on subscriber downtime.
  default_message_ttl = "P1D"
}

# -----------------------------------------------------------------------------
# SUBSCRIPTION: products-subscription
#
# This subscription represents AK.Products listening to integration-events.
# Every message published to the topic is independently delivered here.
# AK.Products uses this to consume OrderCreated events and reserve stock.
#
# WHY INDEPENDENT SUBSCRIPTIONS?
#   If both Products and Notification read from the same subscription, they would
#   compete for messages — one gets it, the other doesn't. Independent subscriptions
#   ensure fan-out: every subscriber gets every message, independently.
#   This is the pub/sub contract: producers don't know their consumers.
# -----------------------------------------------------------------------------
resource "azurerm_servicebus_subscription" "products" {
  name               = "products-subscription"
  topic_id           = azurerm_servicebus_topic.integration_events.id
  max_delivery_count = 10

  # Dead-letter messages that expire or exceed max_delivery_count.
  # See order-commands queue comment above for the rationale.
  dead_lettering_on_message_expiration = true
}

# -----------------------------------------------------------------------------
# SUBSCRIPTION: notification-subscription
#
# AK.Notification listens to integration-events via this subscription.
# It independently receives a copy of every event — OrderCreated, PaymentSucceeded,
# etc. — and sends the appropriate email or SMS to the customer.
# Adding a third subscriber (e.g., analytics-subscription) requires only adding
# a new azurerm_servicebus_subscription resource — no other changes.
# -----------------------------------------------------------------------------
resource "azurerm_servicebus_subscription" "notification" {
  name               = "notification-subscription"
  topic_id           = azurerm_servicebus_topic.integration_events.id
  max_delivery_count = 10

  dead_lettering_on_message_expiration = true
}

# -----------------------------------------------------------------------------
# KEY VAULT SECRET — Service Bus connection string
#
# The namespace's default primary connection string has Manage + Send + Listen
# permissions on the entire namespace. This is broad — in production, create
# per-entity authorization rules with only the permissions each service needs.
# For dev, the default connection string is acceptable.
#
# INTERIM APPROACH (same as Cosmos DB):
#   Week 3: SP writes the secret; application reads it from Key Vault
#   Week 5: Transition to Managed Identity — no SAS key needed; services
#           authenticate to Service Bus via their pod-assigned managed identity
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "servicebus_connection_string" {
  name         = "servicebus-connection-string"
  value        = azurerm_servicebus_namespace.this.default_primary_connection_string
  key_vault_id = var.key_vault_id

  tags = merge(var.tags, {
    secret_type = "connection-string"
    managed_by  = "terraform"
  })
}
