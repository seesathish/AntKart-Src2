# =============================================================================
# EVENT GRID MODULE
# File: infrastructure/modules/eventgrid/main.tf
#
# PURPOSE:
#   Demonstrates Event Grid's routing semantics alongside the existing Service Bus
#   messaging semantics. Creates one custom topic and one event subscription that
#   routes UserRegistered events → a dedicated Service Bus queue.
#
# EVENT GRID vs SERVICE BUS — when to use which:
#
#   Service Bus (existing pattern):
#     - Messaging semantics: durable delivery, at-least-once, dead-letter queue
#     - Pull model: consumers poll for messages on their schedule
#     - Ordering: FIFO within sessions
#     - Best for: commands, SAGA choreography, ordered processing, retry with DLQ
#     - AntKart uses it for: OrderCreated → Notification, SAGA steps, Payments events
#
#   Event Grid (this module):
#     - Routing semantics: fan-out filtering, push delivery to multiple endpoints
#     - Push model: Event Grid pushes to subscribers when an event arrives
#     - Retry: built-in exponential back-off (up to 24 hours)
#     - Best for: system events, multi-subscriber fan-out, webhook delivery,
#                 triggering Azure Functions/Logic Apps on resource changes
#     - AntKart uses it for: UserRegistered → Service Bus queue (demo routing)
#
# DEMO FLOW:
#   AK.UserIdentity.RegisterAsync()
#     → publishes to Event Grid topic (HTTP POST with EventGridEvent)
#     → Event Grid routes to Service Bus queue 'user-registered-events'
#     → MassTransit consumer (or future Azure Function trigger) processes the queue
#
# WHY Service Bus as the Event Grid endpoint?
#   A direct Event Grid → Function/webhook delivery requires a public HTTPS endpoint.
#   Routing through Service Bus avoids this requirement for local dev and adds
#   a durable buffer so messages survive if the downstream is temporarily unavailable.
# =============================================================================

# Custom Event Grid topic — the endpoint AK.UserIdentity publishes to.
# A "custom topic" accepts events from our own application code (vs a "system topic"
# which accepts events from Azure services like Blob Storage or Container Registry).
resource "azurerm_eventgrid_topic" "main" {
  name                = var.topic_name
  location            = var.location
  resource_group_name = var.resource_group_name

  # input_schema = "EventGridSchema" (default) — our publisher must send EventGridEvent objects.
  # Alternative: "CloudEventSchemaV1_0" — CNCF standard; preferred for new greenfield work.
  # We use the default for simplicity in this demo.

  tags = var.tags
}

# =============================================================================
# EVENT SUBSCRIPTION → Service Bus Queue
#
# Filters events by type "AntKart.UserRegistered" and routes them to the
# 'user-registered-events' queue on the existing Service Bus namespace.
# =============================================================================
resource "azurerm_eventgrid_event_subscription" "user_registered_to_sb" {
  name  = "${var.topic_name}-user-registered-sub"
  scope = azurerm_eventgrid_topic.main.id

  # Delivery destination: Service Bus queue (durable buffer before processing)
  service_bus_queue_endpoint_id = var.service_bus_queue_id

  # Filter to only forward UserRegistered events — other event types published
  # to this topic are silently dropped by this subscription.
  # This is Event Grid's routing superpower: one topic, many typed subscribers.
  included_event_types = ["AntKart.UserRegistered"]

  # Retry policy: up to 10 attempts over 24 hours with exponential back-off.
  # After all retries exhausted, the event is sent to the dead-letter location
  # (if configured — omitted here for demo simplicity).
  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 1440 # 24 hours in minutes
  }
}
