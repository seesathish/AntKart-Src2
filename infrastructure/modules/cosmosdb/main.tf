# =============================================================================
# COSMOS DB MODULE — MAIN
# File: infrastructure/modules/cosmosdb/main.tf
#
# PURPOSE:
#   Creates an Azure Cosmos DB account using the MongoDB API, a database,
#   and stores the connection string as a Key Vault secret so services never
#   need to handle the credential directly.
#
# WHY COSMOS DB WITH MONGODB API?
#   AntKart's AK.Products service was built in Phase 1 using MongoDB with the
#   official MongoDB .NET driver. Cosmos DB's MongoDB API is wire-compatible
#   with MongoDB — the same driver, the same BSON documents, the same queries.
#   This means AK.Products can point at Cosmos DB with a single connection
#   string change and no code rewrite. We get:
#     - Managed service: no VM, no ops, no replica set management
#     - Azure-native: private endpoints, RBAC, Azure Monitor integration
#     - Global distribution: add regions with one Terraform change (later)
#     - Serverless billing: pay per request, not per hour
#
# SERVERLESS vs PROVISIONED vs AUTOSCALE:
#
#   ┌─────────────────┬──────────────────────────────────────────────────────┐
#   │ Serverless      │ Pay per Request Unit (RU) consumed. No idle cost.    │
#   │ (chosen)        │ ~$0.25/million RUs. Perfect for dev and low/variable │
#   │                 │ traffic. Max 5,000 RU/s burst. No SLA on throughput. │
#   ├─────────────────┼──────────────────────────────────────────────────────┤
#   │ Provisioned     │ Reserve RU/s upfront. Billed whether used or not.    │
#   │                 │ 400 RU/s minimum = ~$23/month. Guarantees throughput.│
#   ├─────────────────┼──────────────────────────────────────────────────────┤
#   │ Autoscale       │ Scales 10%-100% of max RU/s automatically. Minimum   │
#   │                 │ 1,000 RU/s = ~$6/month baseline. For variable prod   │
#   │                 │ workloads that need throughput guarantees.            │
#   └─────────────────┴──────────────────────────────────────────────────────┘
#
#   SWITCH TO PROVISIONED/AUTOSCALE WHEN:
#     - Traffic is predictable and sustained (provisioned)
#     - You need a latency SLA (serverless has no SLA on throughput)
#     - A single operation exceeds 5,000 RU/s (serverless burst limit)
#   To switch: remove EnableServerless capability, set throughput on the database.
#   This is a DESTRUCTIVE change — the account must be recreated.
#   Design decision: choose the billing model during account creation, not later.
#
# CONSISTENCY LEVELS:
#   Cosmos DB offers five consistency levels (strongest to weakest):
#     Strong         → Read always sees the latest committed write. Highest latency.
#                      Multi-region Strong is extremely expensive.
#     Bounded Staleness → Reads lag writes by at most K operations or T seconds.
#     Session        → Within a session, reads see your own writes (chosen).
#                      Best balance for user-facing applications.
#     Consistent Prefix → Reads never see out-of-order writes, but may lag.
#     Eventual       → Highest availability, lowest latency. Reads may be stale.
#
#   Session is the right default for AntKart:
#     - A user adds a product → they immediately see it in their next read
#     - Other users may briefly see an older state — acceptable for e-commerce
#     - No latency penalty vs provisioned strong consistency
#
# PRIVATE ENDPOINTS (future hardening):
#   The account is currently accessible over the public internet (with auth).
#   To add a private endpoint:
#     1. Add azurerm_private_endpoint on the pe_subnet_id from networking module
#     2. Add a Private DNS Zone for "privatelink.mongo.cosmos.azure.com"
#     3. Set is_virtual_network_filter_enabled = true and add a network_rule
#   No changes to this module's structure are needed for that upgrade.
# =============================================================================

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# COSMOS DB ACCOUNT
# -----------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "MongoDB"
  tags                = var.tags

  # -------------------------------------------------------------------------
  # MONGODB CAPABILITIES
  #
  # EnableMongo:       Required to activate the MongoDB wire protocol API.
  #                    Without this, the account would default to the Core SQL API.
  # EnableServerless:  Activates pay-per-request billing (no reserved RU/s).
  #                    See module header for serverless vs provisioned comparison.
  #
  # Note: capabilities blocks are repeatable. Each is a separate feature flag.
  # The order matters: EnableMongo must come before EnableServerless.
  # -------------------------------------------------------------------------
  capabilities {
    name = "EnableMongo"
  }

  capabilities {
    name = "EnableServerless"
  }

  # -------------------------------------------------------------------------
  # CONSISTENCY POLICY
  # See module header for explanation of all five levels.
  # -------------------------------------------------------------------------
  consistency_policy {
    consistency_level = "Session"
  }

  # -------------------------------------------------------------------------
  # GEO LOCATION — PRIMARY REGION
  #
  # failover_priority = 0 designates this as the write region (primary).
  # To add a read replica in a second region later:
  #   geo_location {
  #     location          = "westeurope"
  #     failover_priority = 1
  #   }
  # Cosmos DB performs automatic failover if the primary becomes unavailable
  # (with manual failover configured). Adding a second region costs double the RUs.
  # -------------------------------------------------------------------------
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # MongoDB server version. 4.2 is stable and widely supported by the MongoDB
  # .NET driver used in AK.Products. Higher versions (5.0, 7.0) are available
  # if specific features are needed.
  mongo_server_version = "4.2"

  lifecycle {
    # Cosmos DB contains business data (product catalogue in Phase 2+).
    # Accidental destruction would lose data and require restoring from backup.
    # prevent_destroy forces a deliberate code change before any destroy is permitted.
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# COSMOS DB MONGO DATABASE
#
# This maps to the "AKProductsDb" database used by AK.Products in Phase 1.
# The database name is kept consistent so the Products service code needs
# only a connection string change — the database name stays the same.
#
# In serverless mode: no throughput is set here. RUs are consumed and billed
# at the individual operation level automatically.
#
# Collections (equivalent to MongoDB collections) are created by the application
# on first write, not by Terraform. AK.Products creates the "Products" collection
# automatically via MongoDB.Driver's EnsureIndex / implicit collection creation.
# If you want Terraform to own the collection lifecycle (for partition key design
# changes), use azurerm_cosmosdb_mongo_collection — deferred to Week 5.
# -----------------------------------------------------------------------------
resource "azurerm_cosmosdb_mongo_database" "products" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}

# -----------------------------------------------------------------------------
# KEY VAULT SECRET — Cosmos DB connection string
#
# WHY store the connection string in Key Vault (not in code or environment vars)?
#   - The connection string contains the primary key — a secret that grants
#     full read/write access to every document in the account
#   - Storing it in Key Vault means no secret ever appears in a .tf file,
#     a Kubernetes manifest, a CI/CD log, or application config
#   - AKS pods retrieve it at runtime via the Secrets Store CSI Driver (Week 5)
#
# INTERIM APPROACH:
#   Week 3: SP writes the secret; application reads it via az keyvault / SDK
#   Week 5: Transition to Workload Identity — no static secret needed at all;
#           pods use their managed identity to read Key Vault secrets directly
#
# connection_strings[0] = primary read-write connection string (MongoDB format)
#   "mongodb://cosmos-antkart-dev:<key>@cosmos-antkart-dev.mongo.cosmos.azure.com:10255/..."
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  name         = "cosmos-connection-string"
  value        = azurerm_cosmosdb_account.this.connection_strings[0]
  key_vault_id = var.key_vault_id

  tags = merge(var.tags, {
    secret_type = "connection-string"
    managed_by  = "terraform"
  })
}
