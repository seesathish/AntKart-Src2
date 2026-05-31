# AntKart Cloud Migration Log

This document is a permanent, running record of every code change made during AntKart's migration from a local Docker Compose stack (Phase 1) to a cloud-native Azure platform (Phase 2). Each section covers one week of work, explains every file that changed, and explains *why* the change was made — not just *what* changed.

This document is maintained in parallel with `DevelopmentGuide.md`. The Development Guide explains concepts and teaches; this document records decisions and diffs with reasoning. When in doubt about why a file looks the way it does, start here.

---

## How to read this document

Each change entry has:
- **File** — the exact path relative to the repo root
- **Change** — what was added, removed, or replaced
- **Reason** — the architectural or technical justification

---

## Week 3 — Data and Messaging Infrastructure

Week 3 added the managed Azure services that replace two Docker containers: MongoDB → Cosmos DB (MongoDB API), and RabbitMQ → Azure Service Bus. No application code changed this week — only Terraform infrastructure files and documentation.

### Infrastructure files added

| File | Purpose |
|------|---------|
| `infrastructure/modules/cosmosdb/main.tf` | Defines the Cosmos DB account (MongoDB API, Serverless), the `antkart-products` database, and a Key Vault secret for the connection string |
| `infrastructure/modules/cosmosdb/variables.tf` | Input variables: name, location, resource_group_name, database_name, key_vault_id, tags |
| `infrastructure/modules/cosmosdb/outputs.tf` | Outputs: id, name, endpoint, database_name, connection_string (sensitive) |
| `infrastructure/modules/cosmosdb/README.md` | Module documentation with cost model and consistency level rationale |
| `infrastructure/modules/servicebus/main.tf` | Defines the Service Bus namespace, `order-commands` queue, `integration-events` topic, `products-subscription` and `notification-subscription`, and Key Vault secret |
| `infrastructure/modules/servicebus/variables.tf` | Input variables: name, location, resource_group_name, sku, key_vault_id, tags |
| `infrastructure/modules/servicebus/outputs.tf` | Outputs: namespace_id, namespace_name, queue ids, topic id, connection_string (sensitive) |
| `infrastructure/modules/servicebus/README.md` | Module documentation with Queue vs Topic explanation and SKU comparison |
| `infrastructure/environments/dev/cosmosdb/terragrunt.hcl` | Wires the cosmosdb module to dev, reads resource-group and key-vault from dependency outputs |
| `infrastructure/environments/dev/servicebus/terragrunt.hcl` | Wires the servicebus module to dev, reads resource-group and key-vault from dependency outputs |
| `docs/adr/ADR-011-cosmosdb-and-servicebus.md` | Architecture Decision Record: why MongoDB API over Core SQL, why Serverless, why Standard SKU |

### Key decisions in Week 3

**Cosmos DB: MongoDB API + Serverless**
AK.Products uses `MongoDB.Driver`. The MongoDB API is wire-compatible — the connection string format changes but zero application code changes. Serverless billing (pay-per-RU, no idle cost) is correct for intermittent dev workloads.

**Service Bus: Standard SKU**
AntKart requires topics for fan-out (OrderCreated → Products + Notification independently). Basic SKU has no topics. Standard SKU is the minimum viable choice.

**Connection strings stored in Key Vault**
Neither connection string appears in code or config files. Terraform writes them to Key Vault (`cosmos-connection-string`, `servicebus-connection-string`) via `azurerm_key_vault_secret`. Applications read them at runtime via the Secrets Store CSI Driver (Week 7+).

**Week 3 infrastructure entities are teaching constructs**
The `order-commands` queue and `integration-events` topic created in Terraform are illustrative — they show juniors how Service Bus topology works before MassTransit is configured. MassTransit creates its own runtime topology (Week 4). Both can coexist in the same namespace.

---

## Week 4 — RabbitMQ → Azure Service Bus Migration

Week 4 is the first week of application code changes. The messaging transport used by all 6 services that participate in the event-driven architecture (Order, Products, Payments, Notification, ShoppingCart, UserIdentity) was migrated from a local RabbitMQ Docker container to Azure Service Bus, using token-based authentication.

**Zero consumers, sagas, outbox configurations, or integration event types were changed.** MassTransit's abstraction layer means the transport swap touches only configuration and packages.

---

### Change 1: MassTransit transport package swap

**Files changed:**
- `AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj`
- `AK.Order/AK.Order.Infrastructure/AK.Order.Infrastructure.csproj`
- `AK.Products/AK.Products.Infrastructure/AK.Products.Infrastructure.csproj`
- `AK.Payments/AK.Payments.Infrastructure/AK.Payments.Infrastructure.csproj`
- `AK.Notification/AK.Notification.Infrastructure/AK.Notification.Infrastructure.csproj`
- `AK.ShoppingCart/AK.ShoppingCart.Infrastructure/AK.ShoppingCart.Infrastructure.csproj`
- `AK.UserIdentity/AK.UserIdentity.API/AK.UserIdentity.API.csproj`

**What changed:**

In each `.csproj`:
```xml
<!-- REMOVED from all 7 projects -->
<PackageReference Include="MassTransit.RabbitMQ" Version="8.3.6" />

<!-- ADDED to AK.BuildingBlocks only -->
<PackageReference Include="MassTransit.Azure.ServiceBus.Core" Version="8.3.6" />
<PackageReference Include="Azure.Identity" Version="1.13.2" />
```

**Reason — why only BuildingBlocks gets the new packages:**

`MassTransit.RabbitMQ` was listed in all 7 projects, but only `AK.BuildingBlocks/Messaging/MassTransitExtensions.cs` actually called `UsingRabbitMq()`. The other projects had the package as a leftover explicit reference — the transport API was never called from them directly.

Because the transport configuration is centralised in `MassTransitExtensions.cs` (in BuildingBlocks), only BuildingBlocks needs `MassTransit.Azure.ServiceBus.Core`. All other projects consume the transport indirectly through the BuildingBlocks method.

`Azure.Identity` provides `DefaultAzureCredential` — the credential chain object that makes token-based auth work (see Change 2).

**Reason — why MassTransit.RabbitMQ was removed everywhere:**

The `MassTransit.RabbitMQ` package pulls in the `RabbitMQ.Client` NuGet, which pulls in AMQP connection classes. With the transport replaced by Service Bus, these classes are dead weight. Removing them shrinks the build graph, eliminates a dependency that is no longer needed, and prevents accidental use of RabbitMQ APIs in future code.

---

### Change 2: MassTransitExtensions.cs — transport replacement

**File:** `AK.BuildingBlocks/AK.BuildingBlocks/Messaging/MassTransitExtensions.cs`

**What changed:**

The method was renamed and the transport block replaced:

```csharp
// BEFORE
public static IServiceCollection AddRabbitMqMassTransit(
    this IServiceCollection services,
    IConfiguration configuration,
    string servicePrefix,
    Action<IBusRegistrationConfigurator> configure)
{
    var host     = configuration["RabbitMq:Host"]        ?? "localhost";
    var vhost    = configuration["RabbitMq:VirtualHost"] ?? "/";
    var username = configuration["RabbitMq:Username"]    ?? "guest";
    var password = configuration["RabbitMq:Password"]    ?? "guest";

    services.AddMassTransit(x =>
    {
        x.SetEndpointNameFormatter(new KebabCaseEndpointNameFormatter(servicePrefix, false));
        configure(x);
        x.UsingRabbitMq((ctx, cfg) =>
        {
            cfg.Host(host, vhost, h =>
            {
                h.Username(username);
                h.Password(password);
            });
            cfg.UseMessageRetry(r => r.Incremental(3, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2)));
            cfg.ConfigureEndpoints(ctx);
        });
    });
    return services;
}

// AFTER
public static IServiceCollection AddServiceBusMassTransit(
    this IServiceCollection services,
    IConfiguration configuration,
    string servicePrefix,
    Action<IBusRegistrationConfigurator> configure)
{
    var fullyQualifiedNamespace = configuration["ServiceBus:FullyQualifiedNamespace"]
        ?? "sb-antkart-dev.servicebus.windows.net";

    services.AddMassTransit(x =>
    {
        x.SetEndpointNameFormatter(new KebabCaseEndpointNameFormatter(servicePrefix, false));
        configure(x);
        x.UsingAzureServiceBus((ctx, cfg) =>
        {
            cfg.Host(new Uri($"sb://{fullyQualifiedNamespace}/"), h =>
            {
                h.TokenCredential = new DefaultAzureCredential();
            });
            cfg.UseMessageRetry(r => r.Incremental(3, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2)));
            cfg.ConfigureEndpoints(ctx);
        });
    });
    return services;
}
```

**Reason — why `UsingAzureServiceBus` instead of `UsingRabbitMq`:**

`UsingRabbitMq` tells MassTransit to use the AMQP protocol to connect to a RabbitMQ broker. `UsingAzureServiceBus` tells MassTransit to use the Azure Service Bus SDK (`Azure.Messaging.ServiceBus`) to connect to Azure. Same API surface for consumers and sagas — different wire protocol underneath.

**Reason — why `DefaultAzureCredential` instead of a connection string:**

A connection string (`Endpoint=sb://...;SharedAccessKey=...`) is a secret. It must be stored securely, rotated periodically, and never committed to source control. If it leaks, anyone with it has full access to the namespace until it's revoked.

`DefaultAzureCredential` is a credential chain — it tries multiple authentication sources in order and stops at the first that succeeds:

| Order | Source | Active when |
|-------|--------|-------------|
| 1 | `EnvironmentCredential` | `ARM_CLIENT_ID` + `ARM_CLIENT_SECRET` env vars set |
| 2 | `WorkloadIdentityCredential` | Running in a Kubernetes pod with federated identity (AKS, Week 7) |
| 3 | `ManagedIdentityCredential` | Running on Azure VM, App Service, etc. |
| 4 | `AzureCliCredential` | Developer has run `az login` on their machine ← **local dev** |
| 5 | Others | Visual Studio, VS Code auth, etc. |

Locally: `AzureCliCredential` succeeds because the developer has authenticated with `az login`.  
In AKS (Week 7): `WorkloadIdentityCredential` succeeds because the pod has a federated identity mounted at a known path by the Kubernetes service account token projection.

Same code. Same config file. Different credential source — chosen automatically at runtime based on environment. No static secret required in either place.

**Reason — why `h.TokenCredential = new DefaultAzureCredential()`:**

MassTransit's Azure Service Bus host configurator exposes `TokenCredential` as a property. Setting it tells the underlying `Azure.Messaging.ServiceBus.ServiceBusClient` to use token auth instead of a connection string. The `sb://` URI prefix tells MassTransit the namespace FQDN without implying a connection string.

**Reason — why the method was renamed:**

The old name `AddRabbitMqMassTransit` was accurate — it registered RabbitMQ. After the migration, that name would be misleading. `AddServiceBusMassTransit` reflects the actual transport. All 6 call sites were updated to match.

**What did NOT change in this method:**

- `KebabCaseEndpointNameFormatter(servicePrefix, false)` — unchanged. The prefix ensures each service gets uniquely named subscriptions on shared topics.
- `UseMessageRetry(r => r.Incremental(3, ...))` — unchanged. Retry policy is transport-agnostic.
- `ConfigureEndpoints(ctx)` — unchanged. MassTransit still auto-creates endpoints for all registered consumers and sagas.
- The `configure` callback — unchanged. Each service still registers its own consumers/sagas/outbox in the same way.

---

### Change 3: appsettings.json — config key replacement

**Files changed (6 services):**
- `AK.Order/AK.Order.API/appsettings.json`
- `AK.Products/AK.Products.API/appsettings.json`
- `AK.Payments/AK.Payments.API/appsettings.json`
- `AK.Notification/AK.Notification.API/appsettings.json`
- `AK.ShoppingCart/AK.ShoppingCart.API/appsettings.json`
- `AK.UserIdentity/AK.UserIdentity.API/appsettings.json`

**What changed in each file:**

```json
// REMOVED from 5 services (UserIdentity never had this block)
"RabbitMq": {
  "Host": "localhost",
  "VirtualHost": "/",
  "Username": "guest",
  "Password": "guest"
}

// ADDED to all 6 services
"ServiceBus": {
  "FullyQualifiedNamespace": "sb-antkart-dev.servicebus.windows.net"
}
```

**Reason — why the namespace FQDN is in appsettings (not a secret):**

The namespace hostname (`sb-antkart-dev.servicebus.windows.net`) is the public DNS name of the Service Bus namespace. It is not a secret — anyone can resolve it. The old RabbitMQ config contained a username and password, which were secrets (even if they were `guest`/`guest` in dev). The new config contains no credentials at all.

In AKS (Week 7), `ServiceBus:FullyQualifiedNamespace` will be injected via a Kubernetes ConfigMap (not a Secret), because it genuinely is not sensitive.

**Reason — why a single FQDN instead of four separate RabbitMQ fields:**

RabbitMQ needed four values: host, virtual host, username, password. Azure Service Bus with token auth needs one: the namespace hostname. The credential is supplied at runtime by the Azure SDK. This is a concrete improvement in configuration simplicity that token auth delivers.

---

### Change 4: ServiceCollectionExtensions.cs call-site renames

**Files changed:**
- `AK.Order/AK.Order.Infrastructure/Extensions/ServiceCollectionExtensions.cs`
- `AK.Products/AK.Products.Infrastructure/Extensions/ServiceCollectionExtensions.cs`
- `AK.Payments/AK.Payments.Infrastructure/Extensions/ServiceCollectionExtensions.cs`
- `AK.Notification/AK.Notification.Infrastructure/Extensions/ServiceCollectionExtensions.cs`
- `AK.ShoppingCart/AK.ShoppingCart.Infrastructure/Extensions/ServiceCollectionExtensions.cs`

**What changed in each file:**

```csharp
// BEFORE
services.AddRabbitMqMassTransit(configuration, "<prefix>", cfg => { ... });

// AFTER
services.AddServiceBusMassTransit(configuration, "<prefix>", cfg => { ... });
```

**Reason:** The method was renamed in BuildingBlocks. All call sites must match. No other logic changed — the service prefix, the consumer registrations, the saga registrations, and the outbox registrations are identical before and after.

---

### Change 5: UserIdentity Program.cs call-site rename

**File:** `AK.UserIdentity/AK.UserIdentity.API/Program.cs`

**What changed:**

```csharp
// BEFORE
builder.Services.AddRabbitMqMassTransit(builder.Configuration, "identity", _ => { });

// AFTER
builder.Services.AddServiceBusMassTransit(builder.Configuration, "identity", _ => { });
```

**Reason:** UserIdentity registers MassTransit directly in `Program.cs` (no Infrastructure layer) because it has no consumers — only a publisher (`IPublishEndpoint` injected into `KeycloakService`). The rename is a call-site update only; behaviour is unchanged.

**Why UserIdentity has no consumers:**  
UserIdentity publishes `UserRegisteredIntegrationEvent` when a user registers (to trigger a welcome email from AK.Notification). It does not consume any events from other services. The empty callback `_ => { }` is intentional — MassTransit still needs to be registered so `IPublishEndpoint` is available in the DI container.

---

### Change 6: docker-compose.yml — RabbitMQ removal

**File:** `docker-compose.yml`

**What was removed:**

1. The entire `rabbitmq` service definition:
   ```yaml
   # REMOVED
   rabbitmq:
     image: rabbitmq:3.13-management
     container_name: antkart-rabbitmq
     ports: ["5672:5672", "15672:15672"]
     environment: { RABBITMQ_DEFAULT_USER: guest, RABBITMQ_DEFAULT_PASS: guest }
     healthcheck: ...
     volumes: [rabbitmq_data:/var/lib/rabbitmq]
   ```

2. `RabbitMq__*` environment variables from all 6 messaging services (Products, ShoppingCart, Order, Payments, UserIdentity, Notification):
   ```yaml
   # REMOVED from each service
   - RabbitMq__Host=rabbitmq
   - RabbitMq__VirtualHost=/
   - RabbitMq__Username=guest
   - RabbitMq__Password=guest
   ```

3. `rabbitmq: condition: service_healthy` from `depends_on` of all services that had it.

4. `rabbitmq_data` from the top-level `volumes` block.

**What was added:**

`ServiceBus__FullyQualifiedNamespace=sb-antkart-dev.servicebus.windows.net` to each messaging service's environment block.

**Reason — why remove the rabbitmq container:**

The enterprise development model (Week 4+) runs services locally against real Azure cloud services. Keeping a local RabbitMQ container would create two messaging systems: the cloud one (Service Bus, used by the code) and a local one (RabbitMQ, unused but consuming memory and startup time). Removing it makes the intent explicit: messaging goes through Azure Service Bus.

**Reason — why the compose file still exists at all:**

Docker Compose is still used for non-messaging infrastructure that is hard to share via cloud:
- Keycloak (identity — no managed Azure equivalent in the free tier)
- MongoDB (local dev still uses it; Cosmos DB is for cloud)
- PostgreSQL (local dev database)
- Redis (local cart storage)
- Elasticsearch + Kibana (observability local stack)
- Mailhog (local email trap)

These services do not have the same enterprise-cloud migration as messaging. They remain local for now and will be migrated in later weeks.

**Reason — why `ServiceBus__FullyQualifiedNamespace` in compose:**

When the full Docker Compose stack is run (e.g., for a full-stack local integration test), the containers need to know which Service Bus namespace to connect to. The FQDN is not a secret and is safe in a compose file. Authentication from a container uses the `EnvironmentCredential` (ARM_ env vars) or Workload Identity — not the compose file.

---

### Change 7: docker-compose.override.yml — RabbitMQ removal

**File:** `docker-compose.override.yml`

**What was removed:**

```yaml
# REMOVED
rabbitmq:
  ports:
    - "5672:5672"
    - "15672:15672"
```

**Reason:** The override file only provides port mapping for the rabbitmq service in development. Since the service itself was removed from the base compose file, the override entry is dead configuration. Removed to keep the override file consistent.

---

### What did NOT change in Week 4

The following are explicitly unchanged, confirming that MassTransit's abstraction held:

| Component | Why unchanged |
|-----------|--------------|
| All consumer classes (12 consumers across 5 services) | Business logic has no transport coupling |
| OrderSaga state machine | Correlated by OrderId, persisted to PostgreSQL — pure MassTransit abstraction |
| EF Core Outbox (Order + Payments) | Writes to local DB table; MassTransit delivers via the bus — transport-agnostic |
| All integration event records (9 types in BuildingBlocks) | Plain C# records with no transport dependencies |
| All 618 unit and integration tests | Use MassTransit in-memory test harness — no transport package involved |
| SAGA PostgreSQL persistence | `EntityFrameworkRepository` is an EF Core concern, not a transport concern |
| Retry policy (3 attempts, incremental backoff) | `UseMessageRetry` is transport-agnostic in MassTransit |
| Endpoint name formatter (KebabCase + prefix) | Transport-agnostic; same subscriptions names will be created on Service Bus |

---

### MassTransit topology on Azure Service Bus (auto-created)

When any of the 6 services starts and connects to Service Bus for the first time, MassTransit automatically creates the following Azure resources (requires `Azure Service Bus Data Owner` role for Manage permission):

**Topics** (one per message type, named from the .NET type full name):
```
ak.buildingblocks.messaging.integrationevents:ordercreatedintegrationevent
ak.buildingblocks.messaging.integrationevents:orderconfirmedintegrationevent
ak.buildingblocks.messaging.integrationevents:ordercancelledintegrationevent
ak.buildingblocks.messaging.integrationevents:stockreservedintegrationevent
ak.buildingblocks.messaging.integrationevents:stockreservationfailedintegrationevent
ak.buildingblocks.messaging.integrationevents:paymentinitiatedintegrationevent
ak.buildingblocks.messaging.integrationevents:paymentsucceededintegrationevent
ak.buildingblocks.messaging.integrationevents:paymentfailedintegrationevent
ak.buildingblocks.messaging.integrationevents:userregisteredintegrationevent
```

**Subscriptions** (one per consumer endpoint, named `<servicePrefix>-<consumer-kebab>`):
```
order-order-saga                      ← OrderSaga (on ordercreatedintegrationevent, stockreserved*, etc.)
order-order-confirmed                 ← OrderConfirmedConsumer
order-order-cancelled                 ← OrderCancelledConsumer
order-payment-succeeded               ← PaymentSucceededConsumer
order-payment-failed                  ← PaymentFailedConsumer
products-reserve-stock                ← ReserveStockConsumer
payments-order-confirmed              ← OrderConfirmedConsumer (no-op stub)
notification-user-registered          ← UserRegisteredConsumer
notification-order-created            ← OrderCreatedConsumer
notification-order-confirmed          ← OrderConfirmedConsumer
notification-order-cancelled          ← OrderCancelledConsumer
notification-payment-succeeded        ← PaymentSucceededConsumer
notification-payment-failed           ← PaymentFailedConsumer
cart-clear-cart-on-order-confirmed    ← ClearCartOnOrderConfirmedConsumer
```

Each subscription is independently bound to its topic — fan-out semantics. A message published to `ordercreatedintegrationevent` is independently delivered to `order-order-saga`, `products-reserve-stock`, `notification-order-created`, and `cart-clear-cart-on-order-confirmed`.

These are separate from the Week 3 Terraform-created entities (`order-commands`, `integration-events`). Both coexist in the namespace — the Terraform ones are teaching constructs, MassTransit's are runtime entities.

---

## Future Weeks (planned)

| Week | Change |
|------|--------|
| 5 | AKS cluster provisioning (Terraform), ingress controller, namespace setup |
| 6 | Dockerfiles review, image push to ACR, Helm chart scaffolding |
| 7 | Deploy services to AKS, Workload Identity for Service Bus + Key Vault, kubectl port-forward for debugging |
| 8 | Observability: Application Insights SDK integration, distributed tracing |
| 9 | Auto-scaling, resource limits, production hardening |

Each week's changes will be documented here with the same format: file, what changed, why it changed.
