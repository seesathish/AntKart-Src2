# =============================================================================
# IDENTITY MODULE — MAIN
# File: infrastructure/modules/identity/main.tf
#
# PURPOSE:
#   Creates User-Assigned Managed Identities for AntKart microservices and
#   grants them the Azure RBAC roles they need to access cloud resources.
#   This is the foundation for Workload Identity in AKS (Week 7).
#
# WHY USER-ASSIGNED MANAGED IDENTITY (not System-Assigned)?
#
#   System-Assigned (SAI):
#     - Lifecycle tied to the resource (VM, App Service, AKS node pool)
#     - Created and destroyed with the host resource
#     - You cannot pre-create it before the resource exists
#     - Not usable for Kubernetes Workload Identity federation (needs stable client ID)
#
#   User-Assigned Managed Identity (UAMI):
#     - Exists as an independent Azure resource — lifecycle separate from the host
#     - Can be pre-created and assigned to AKS pods via labels (Week 7)
#     - Its client_id is stable — OIDC federated credentials use it to map
#       "Kubernetes service account in namespace X" → "this Azure identity"
#     - Can be shared across multiple resources if needed (but we use one per service)
#
#   For AntKart, UAMI is the only option for AKS Workload Identity.
#   The entire Workload Identity flow requires a stable managed identity
#   that exists before the AKS cluster or pod.
#
# WHAT IS WORKLOAD IDENTITY?
#
#   Traditional approach (AVOID): embed a client secret or certificate in the
#   pod's environment. Secrets must be rotated, can leak, require coordination.
#
#   Workload Identity (OIDC federation):
#     1. AKS has an OIDC issuer — a URL that serves a JSON Web Key Set (JWKS).
#        It proves "this token was issued to this Kubernetes service account."
#     2. A Federated Credential on the UAMI says:
#        "Tokens from AKS OIDC issuer for k8s service account
#         namespace=ak-products, name=ak-products-sa → I trust them."
#     3. When the pod starts, AKS projects a short-lived service account token
#        into the pod's filesystem (AZURE_FEDERATED_TOKEN_FILE env var).
#     4. DefaultAzureCredential reads that file and presents the token to
#        Azure AD, which exchanges it for a short-lived Azure access token.
#     5. The application now has Azure access with zero secrets, zero rotation.
#
#   KEY INSIGHT: The application code is IDENTICAL for local dev and AKS:
#     Local dev:  DefaultAzureCredential → AzureCliCredential (az login session)
#     AKS pod:    DefaultAzureCredential → WorkloadIdentityCredential (projected token)
#   Same line of code. The credential source is an infrastructure concern, not
#   an application concern. This is already proven by the Service Bus migration in Week 4.
#
# WEEK 7 FEDERATION STEP (not done yet — AKS doesn't exist):
#   When the AKS cluster is provisioned in Week 7, add a federated credential:
#
#   resource "azurerm_federated_identity_credential" "products" {
#     name                = "ak-products-federation"
#     resource_group_name = var.resource_group_name
#     parent_id           = azurerm_user_assigned_identity.products.id
#     audience            = ["api://AzureADTokenExchange"]
#     issuer              = <aks_oidc_issuer_url from aks module outputs>
#     subject             = "system:serviceaccount:ak-products:ak-products-sa"
#     #                      ─────────────────── ─────────── ──────────────
#     #                      k8s namespace       ↑           k8s service account name
#     #                      (your choice)       "system:serviceaccount:" prefix
#   }
#
#   The issuer URL and the k8s namespace/service account are defined in Week 7.
#   The client_id output from this module is what you annotate the k8s service
#   account with: azure.workload.identity/client-id: <client_id>
# =============================================================================

# -----------------------------------------------------------------------------
# MANAGED IDENTITY — AK.Products service
#
# This identity will be used in AKS (Week 7) by the ak-products pod.
# Locally, developers use their own az login identity; the managed identity
# is only active when running in AKS with Workload Identity configured.
#
# Naming convention: mi-ak-<service>-<environment>
#   mi   = Managed Identity (Azure naming convention abbreviation)
#   ak   = AntKart
#   products = the microservice this identity represents
#   dev  = environment
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "products" {
  name                = var.products_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# RBAC — Key Vault Secrets User on kv-antkart-dev
#
# WHY THIS ROLE?
#   AK.Products reads the Cosmos DB connection string from Key Vault at startup.
#   The pod's managed identity needs permission to read (not manage) secrets.
#
# KEY VAULT SECRETS USER (read-only):
#   Built-in role. Grants:
#     - Get Secret  → read the secret value (connection string)
#     - List Secrets → enumerate secret names (not needed, but included)
#   Does NOT grant:
#     - Set/Delete Secret → write or delete secrets (Terraform SP has this via Secrets Officer)
#
# SCOPE: the Key Vault resource specifically.
#   Granting at subscription or resource group scope would give this identity
#   read access to secrets in ALL vaults in that scope — unnecessary and insecure.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "products_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.products.principal_id
}

# -----------------------------------------------------------------------------
# RBAC — Azure Service Bus Data Owner on sb-antkart-dev
#
# WHY THIS ROLE?
#   AK.Products uses Azure Service Bus (via MassTransit) to:
#     - Subscribe to OrderCreatedIntegrationEvent (receive messages via ReserveStockConsumer)
#     - Publish StockReservedIntegrationEvent / StockReservationFailedIntegrationEvent
#
#   MassTransit also creates topics and subscriptions at startup (auto-topology),
#   which requires the Manage permission on the namespace.
#
# AZURE SERVICE BUS DATA OWNER:
#   Grants: Manage + Send + Listen (all three data-plane permissions)
#   This is the same role assigned to developer identities in DevelopmentGuide Step 4.1.
#
# LEAST-PRIVILEGE NOTE:
#   Ideally each service would get separate Send and Listen roles on only
#   the topics/queues it actually uses. Data Owner on the whole namespace is
#   broader than needed. For dev this is acceptable; for prod, tighten to:
#     - Azure Service Bus Data Sender on topics it publishes to
#     - Azure Service Bus Data Receiver on subscriptions it reads from
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "products_sb_data_owner" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_user_assigned_identity.products.principal_id
}
