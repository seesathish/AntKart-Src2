using AK.BuildingBlocks.Messaging.IntegrationEvents;
using AK.Notification.Application.Commands;
using AK.Notification.Application.Templates;
using AK.Notification.Domain.Enums;
using MediatR;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace AK.Notification.Functions.Functions;

// Azure Function (isolated worker, Consumption plan) triggered by Service Bus messages.
//
// WHY a Function instead of a MassTransit consumer?
//   The MassTransit consumer runs inside the long-lived Notification API process.
//   The Function scales to zero between messages and spins up only when messages arrive —
//   ideal for low-frequency, latency-tolerant events like welcome emails and order confirmations.
//
// Service Bus wiring:
//   - Topic:        integration-events  (same topic all services publish to)
//   - Subscription: notification-subscription  (fan-out; same messages the consumer receives)
//   - Auth:         DefaultAzureCredential → system-assigned managed identity of the Function App
//                   (no connection string; Service Bus Data Receiver role assigned via Terraform)
//
// The function body mirrors OrderCreatedConsumer — delegates to SendNotificationCommand via
// MediatR so the email pipeline (template rendering, DB persistence, MailKit delivery) is unchanged.
public class OrderCreatedNotificationFunction(IMediator mediator, ILogger<OrderCreatedNotificationFunction> logger)
{
    [Function(nameof(OrderCreatedNotificationFunction))]
    public async Task Run(
        [ServiceBusTrigger(
            topicName:        "integration-events",
            subscriptionName: "notification-subscription",
            Connection        = "ServiceBusConnection",
            IsSessionsEnabled = false)]
        string messageBody,
        FunctionContext context)
    {
        OrderCreatedIntegrationEvent? evt;
        try
        {
            evt = JsonSerializer.Deserialize<OrderCreatedIntegrationEvent>(messageBody,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException ex)
        {
            // Malformed messages should not be retried — log and abandon.
            logger.LogError(ex, "Failed to deserialize OrderCreatedIntegrationEvent");
            return;
        }

        if (evt is null)
        {
            logger.LogWarning("Received null OrderCreatedIntegrationEvent body");
            return;
        }

        var itemSummaries = evt.Items
            .Select(i => $"{i.Quantity}x {i.Sku} @ ₹{i.UnitPrice:N2}")
            .ToList();

        await mediator.Send(new SendNotificationCommand(
            evt.UserId,
            NotificationChannel.Email,
            NotificationTemplateType.OrderConfirmation,
            evt.CustomerEmail,
            new OrderConfirmationModel(evt.CustomerName, evt.OrderNumber, evt.TotalAmount, itemSummaries)),
            context.CancellationToken);

        logger.LogInformation("Order-created notification sent for order {OrderNumber}", evt.OrderNumber);
    }
}
