# Architecture Decision Records

This index lists every ADR for the AntKart platform. Foundational ADRs (F-prefix) document the bedrock architectural choices made before the numbered series began. Numbered ADRs (001–014) document decisions made during Phase 1 (application layer) and Phase 2 (cloud infrastructure).

---

## Foundational ADRs

These two ADRs document the architectural pillars that all subsequent decisions build on.

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-F1](ADR-F1-microservices-architecture.md) | Microservices Architecture — 12-Factor, cloud-native pillars, monolith vs modular monolith vs microservices | Accepted |
| [ADR-F2](ADR-F2-clean-architecture-and-ddd.md) | Clean Architecture and Domain-Driven Design — four layers, dependency rule, 12 tactical patterns | Accepted |

---

## Phase 1 — Application Architecture

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-polyglot-persistence.md) | Polyglot Persistence — one database per service, technology chosen per access pattern | Accepted |
| [ADR-002](ADR-002-saga-orchestration.md) | SAGA Orchestration — MassTransit state machine for distributed Order → Stock → Payment flow | Accepted |
| [ADR-003](ADR-003-ocelot-api-gateway.md) | Ocelot API Gateway — single client entry point, JWT passthrough, rate limiting, QoS | Accepted |
| [ADR-004](ADR-004-masstransit-over-raw-rabbitmq.md) | MassTransit over Raw RabbitMQ | Accepted |
| [ADR-005](ADR-005-shared-ddd-contracts-in-buildingblocks.md) | Shared DDD Contracts in AK.BuildingBlocks — Entity, StringEntity, IDomainEvent, ValueObject | Accepted |
| [ADR-006](ADR-006-domain-events-vs-integration-events.md) | Domain Events vs Integration Events | Accepted |
| [ADR-007](ADR-007-CQRS-and-MediatR.md) | CQRS and MediatR as the Internal Application Pattern | Accepted |
| [ADR-008](ADR-008-Repository-Specification-and-Unit-of-Work.md) | Repository, Specification, and Unit of Work | Accepted |

---

## Phase 2 — Cloud Infrastructure

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-009](ADR-009-iac-with-terraform-terragrunt.md) | Infrastructure-as-Code with Terraform and Terragrunt | Accepted |
| [ADR-010](ADR-010-key-vault-rbac-and-observability-foundation.md) | Key Vault RBAC and Observability Foundation | Accepted |
| [ADR-011](ADR-011-cosmosdb-and-servicebus.md) | Cosmos DB and Azure Service Bus | Accepted |
| [ADR-012](ADR-012-messaging-migration-to-service-bus.md) | Messaging Migration to Azure Service Bus | Accepted |
| [ADR-013](ADR-013-data-migration-cosmosdb-and-workload-identity.md) | Data Migration — Cosmos DB and Workload Identity | Accepted |
| [ADR-014](ADR-014-entra-id-functions-eventgrid.md) | Microsoft Entra ID, Azure Functions Isolated Worker, and Event Grid | Accepted |
| [ADR-015](ADR-015-aks-workload-identity-base-image.md) | AKS Cluster, Workload Identity, and Custom Hardened Base Image | Accepted |
