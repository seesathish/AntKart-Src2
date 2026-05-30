# =============================================================================
# ACR MODULE — MAIN
# File: infrastructure/modules/acr/main.tf
#
# PURPOSE:
#   Creates an Azure Container Registry (ACR) — the private Docker registry
#   where all AntKart microservice images are pushed by CI/CD and pulled by AKS.
#
# WHY ACR INSTEAD OF DOCKER HUB?
#   Docker Hub is public by default. For production workloads you want:
#     - Private images (not visible to the world)
#     - Images co-located with Azure (faster AKS pulls, no external egress charge)
#     - Azure RBAC integration (AKS managed identity pulls without any credential)
#     - Geo-replication across regions (Premium tier — available when needed)
#   ACR is the natural choice for an Azure-native deployment.
#
# SKU NOTES — read before choosing:
#   Basic    (~$5/month)  — single region, no private endpoints, no geo-replication.
#                           Images are still private. Correct for dev.
#   Standard (~$20/month) — more throughput and storage; still no private endpoints.
#   Premium  (~$50/month) — required ONLY for:
#                           ∙ Private endpoints (AKS pulls without public internet)
#                           ∙ Geo-replication (images in multiple Azure regions)
#                           ∙ Dedicated data endpoints (compliance requirement)
#
# UPGRADE PATH (documented here so future-you knows what to change):
#   Step 1: Change sku = "Premium" in environments/{env}/acr/terragrunt.hcl
#   Step 2: Add an azurerm_private_endpoint resource (in a new pe module or inline)
#           pointing to the pe_subnet_id output from the networking module
#   Step 3: Add a Private DNS Zone for "privatelink.azurecr.io" (AKS needs this
#           to resolve the registry's private IP instead of the public one)
#   No structural changes to this module are required — the "Basic now, Premium later"
#   design is already accounted for in the variable definitions below.
# =============================================================================

# Read the currently-authenticating identity (the Service Principal running Terraform).
# Used here to confirm the deploying identity — no outputs exposed from this data source.
data "azurerm_client_config" "current" {}

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # ---------------------------------------------------------------------------
  # admin_enabled = false — WHY NEVER ENABLE THIS?
  #
  # The admin account is a single shared credential with full push/pull access
  # to every repository in the registry. Using it means:
  #   - Sharing one password with every developer, pipeline, and service
  #   - No audit trail — every action appears as the same "admin" user
  #   - Password rotation requires updating every consumer simultaneously
  #   - If the password leaks, ALL repositories are exposed
  #
  # The correct access model is Azure RBAC with dedicated roles:
  #   AcrPull  → AKS node managed identity (pull images to run workloads)
  #   AcrPush  → CI/CD Service Principal or Workload Identity (push built images)
  #   Individual developers pull using: az acr login --name <registry>
  #   (this authenticates via their personal az login session — no shared password)
  #
  # The AcrPull role assignment for AKS is created in the AKS module, scoped
  # to this registry's ID. See modules/aks/ when that module is built.
  # ---------------------------------------------------------------------------
  admin_enabled = false
}
