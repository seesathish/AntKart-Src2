# Module: cosmosdb

Creates an Azure Cosmos DB account (MongoDB API, serverless) for AntKart's product
catalogue data, plus a database and a Key Vault secret for the connection string.

## What this module does

1. Creates a Cosmos DB account with MongoDB API and serverless billing
2. Applies Session consistency (the right default for user-facing e-commerce)
3. Creates the `antkart-products` MongoDB database
4. Stores the connection string in Key Vault as `cosmos-connection-string`
5. Protects the account with `prevent_destroy = true`

## Why MongoDB API?

AK.Products (Phase 1) uses MongoDB.Driver with `AKProductsDb`. Cosmos DB's MongoDB
API is wire-compatible — same driver, same BSON, same queries. Migration in Week 5
requires only a connection string change.

## Billing model comparison

| Mode | Cost when idle | Cost under load | Throughput SLA | Best for |
|------|---------------|-----------------|----------------|----------|
| Serverless (chosen) | $0 | ~$0.25/million RUs | None | Dev, low/variable traffic |
| Autoscale | ~$6/month min | Scales to max RU/s | Yes | Variable prod workloads |
| Provisioned | Fixed (400 RU/s = ~$23/mo) | Fixed | Yes | Predictable steady traffic |

Switching billing models requires recreating the account (destructive). Choose before first apply.

## Consistency levels (summary)

| Level | Guarantee | AntKart relevance |
|-------|-----------|-------------------|
| Strong | Always latest | Too expensive for multi-region |
| Bounded Staleness | Lag ≤ K ops or T seconds | Overkill for product catalogue |
| **Session** (chosen) | Read-your-own-writes | Right for user-facing e-commerce |
| Consistent Prefix | No out-of-order reads | Weaker than needed |
| Eventual | Highest availability | Too weak for product data |

## Partition keys (design for later)

When the `Products` collection is created via Terraform (`azurerm_cosmosdb_mongo_collection`),
you must choose a partition key. Recommendations for AntKart:
- `/categoryName` — distributes products across categories (even spread if categories are balanced)
- `/id` — always even spread but cross-partition queries for category listing become expensive

For now, AK.Products creates the collection implicitly on first write. The partition key
can be specified in Week 5 when the collection resource is added to Terraform.

## Naming constraint — global uniqueness

Cosmos DB account names must be globally unique.
```bash
az cosmosdb check-name-exists --name cosmos-antkart-dev
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | — | Account name. Lowercase + hyphens, 3-44 chars, globally unique |
| `location` | string | — | Azure region |
| `resource_group_name` | string | — | Resource group |
| `database_name` | string | `"antkart-products"` | MongoDB database name |
| `key_vault_id` | string | — | Key Vault resource ID to store connection string |
| `tags` | map(string) | `{}` | Tags from env.hcl |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `id` | string | Full resource ID |
| `name` | string | Account name |
| `endpoint` | string | Cosmos DB URI (for RBAC/Workload Identity auth in Week 5) |
| `database_name` | string | MongoDB database name |
| `connection_string` | string (sensitive) | Primary connection string (read from Key Vault in apps) |
