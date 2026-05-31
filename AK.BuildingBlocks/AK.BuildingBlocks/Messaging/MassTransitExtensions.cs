using Azure.Identity;
using MassTransit;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AK.BuildingBlocks.Messaging;

// =============================================================================
// MASSTRANSIT + AZURE SERVICE BUS — SHARED TRANSPORT CONFIGURATION
//
// WHAT THIS FILE DOES:
//   This is the single place in the entire AntKart codebase where the messaging
//   transport is configured. Every service that needs the event bus calls
//   AddServiceBusMassTransit() from its Infrastructure ServiceCollectionExtensions.
//
// WHY ONE CENTRAL METHOD?
//   Five services (Order, Products, Payments, Notification, ShoppingCart) all need
//   MassTransit configured the same way. Centralising here means:
//   - Transport change = one file changed (proven by the RabbitMQ → Service Bus migration)
//   - Retry policy, formatter, and endpoint config are consistent across all services
//   - Each service passes its own consumers via the `configure` callback
//
// MIGRATION NOTE (Week 4):
//   This was previously `AddRabbitMqMassTransit` using `UsingRabbitMq()`. The
//   transport was changed to Azure Service Bus with token-based auth (see below).
//   Every consumer, saga, and outbox configuration is unchanged — they work through
//   the MassTransit abstraction and are transport-agnostic.
// =============================================================================
public static class MassTransitExtensions
{
    // -------------------------------------------------------------------------
    // TOKEN-BASED AUTHENTICATION — WHY NO CONNECTION STRING?
    //
    // Traditional messaging configuration uses a connection string:
    //   "Endpoint=sb://sb-antkart-dev.servicebus.windows.net;SharedAccessKey=..."
    //
    // This has three problems:
    //   1. The key is a secret — it must be rotated, stored in Key Vault, and
    //      never committed to source control. One leaked key = full namespace access.
    //   2. The key is long-lived — a stolen key is valid until manually rotated.
    //   3. Different code path locally vs. in AKS — local needs the key in a file;
    //      AKS needs a secret mount or CSI driver.
    //
    // Token-based auth (DefaultAzureCredential) solves all three:
    //   1. No secret in config — only the namespace FQDN (which is not a secret)
    //   2. Tokens are short-lived (1 hour TTL), auto-refreshed by the SDK
    //   3. Same code runs locally and in AKS — credential source changes, code doesn't
    //
    // HOW DefaultAzureCredential WORKS — THE CREDENTIAL CHAIN:
    //   DefaultAzureCredential tries each credential source in order, stopping at the
    //   first one that succeeds. For AntKart:
    //
    //   Locally (developer machine):
    //     1. EnvironmentCredential   — checks ARM_CLIENT_ID / ARM_CLIENT_SECRET env vars
    //     2. WorkloadIdentityCredential — skipped (not in Kubernetes)
    //     3. ManagedIdentityCredential  — skipped (not on Azure VM/App Service)
    //     4. SharedTokenCacheCredential — skipped (no token cache)
    //     5. VisualStudioCredential     — skipped (if not using VS IDE auth)
    //     6. AzureCliCredential      ← SUCCEEDS — uses your `az login` session
    //        The Azure CLI stores a token in ~/.azure/accessTokens.json after login.
    //        DefaultAzureCredential reads it and exchanges it for a Service Bus token.
    //
    //   In AKS (Kubernetes pod, Week 7+):
    //     1. EnvironmentCredential    — skipped (no env vars in pod)
    //     2. WorkloadIdentityCredential ← SUCCEEDS — uses the pod's federated identity
    //        The pod has a projected service account token mounted at a known path.
    //        Azure AD exchanges it for an Azure token with no static key involved.
    //
    //   Same code, both places. The credential source is an environment concern, not
    //   a code concern. This is the modern enterprise authentication pattern.
    //
    // PREREQUISITE:
    //   The identity running the service (developer's `az login` account locally, or
    //   the pod's managed identity in AKS) must have the role:
    //   "Azure Service Bus Data Owner" on the namespace.
    //   This covers: Manage (create topics/queues), Send, and Receive.
    //   Grant it once per identity — Terraform manages it in AKS (Week 7).
    // -------------------------------------------------------------------------

    public static IServiceCollection AddServiceBusMassTransit(
        this IServiceCollection services,
        IConfiguration configuration,
        string servicePrefix,
        Action<IBusRegistrationConfigurator> configure)
    {
        // Read the namespace FQDN from configuration.
        // This is NOT a secret — it's the public hostname of the namespace.
        // Only the token (obtained via DefaultAzureCredential) proves identity.
        var fullyQualifiedNamespace = configuration["ServiceBus:FullyQualifiedNamespace"]
            ?? "sb-antkart-dev.servicebus.windows.net";

        services.AddMassTransit(x =>
        {
            // Prefix + kebab-case naming: ensures unique subscription names when
            // multiple services consume the same message type.
            //
            // Without prefix: both Order and Notification would compete for messages
            // on the same "payment-failed" subscription — only one would get each message.
            //
            // With prefix "order" → subscription "order-payment-failed"
            //      prefix "notification" → subscription "notification-payment-failed"
            // Both subscriptions bind to the same Service Bus topic so each service
            // receives an independent copy of every message (pub/sub fan-out).
            x.SetEndpointNameFormatter(new KebabCaseEndpointNameFormatter(servicePrefix, false));

            // Service-specific consumers, sagas, and outbox configuration.
            // These are transport-agnostic — they were unchanged by the RabbitMQ migration.
            configure(x);

            x.UsingAzureServiceBus((ctx, cfg) =>
            {
                // Connect to the Service Bus namespace using token-based auth.
                //
                // DefaultAzureCredential is the credential object — it does NOT authenticate
                // immediately. It creates a credential chain that lazily tries each source
                // when a token is first needed (on first message send/receive).
                //
                // Locally: resolves to AzureCliCredential (your `az login` session).
                // In AKS: resolves to WorkloadIdentityCredential (pod federated identity).
                // Same line of code. Zero configuration difference between environments.
                //
                // Host() takes a URI (sb://<namespace>/) and a host configurator callback.
                // The TokenCredential property on the configurator tells the Service Bus
                // SDK to use token auth instead of a SAS connection string.
                cfg.Host(new Uri($"sb://{fullyQualifiedNamespace}/"), h =>
                {
                    h.TokenCredential = new DefaultAzureCredential();
                });

                // Global retry policy — unchanged from the RabbitMQ configuration.
                // If a consumer throws, MassTransit retries 3 times with incremental delays
                // (1s, 3s, 5s) before dead-lettering the message. Handles transient DB
                // or network errors without losing messages.
                cfg.UseMessageRetry(r => r.Incremental(3, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2)));

                // Auto-configure all registered consumers and sagas with their endpoint
                // (subscription) names. MassTransit creates the Service Bus topology:
                //   - One topic per message type (named from the .NET type full name)
                //   - One subscription per consumer endpoint (named from servicePrefix + consumer)
                // This requires the "Manage" permission included in "Azure Service Bus Data Owner".
                cfg.ConfigureEndpoints(ctx);
            });
        });

        return services;
    }
}
