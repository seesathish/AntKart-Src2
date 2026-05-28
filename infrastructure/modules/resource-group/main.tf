# =============================================================================
# RESOURCE GROUP MODULE — MAIN
# File: infrastructure/modules/resource-group/main.tf
#
# PURPOSE:
#   Creates an Azure Resource Group — the logical container for all AntKart
#   Azure resources in a given environment. Every Azure resource must belong
#   to exactly one resource group.
#
# WHY a dedicated module for something this simple?
#   1. Consistency: every environment uses the same module, so naming conventions
#      and tagging standards are enforced in one place.
#   2. Lifecycle protection: the prevent_destroy safeguard lives here once, not
#      scattered across environment configs.
#   3. Outputs: downstream modules (networking, AKS, etc.) consume this module's
#      outputs rather than hard-coding the RG name.
#   4. Teaching: understanding how a simple module is wired teaches the pattern
#      used by all complex modules that follow.
#
# AZURE CONCEPT — Resource Group:
#   A resource group is a logical container, not a network boundary. Resources
#   inside it can communicate with resources in other groups. Think of it as a
#   folder for billing, access control (RBAC), and lifecycle management.
#   Deleting a resource group deletes ALL resources inside it — hence the
#   lifecycle block below.
# =============================================================================

# -----------------------------------------------------------------------------
# LOCALS — Module-level values derived from inputs or hard-coded defaults
#
# WHY use locals for default tags?
#   Some tags should always be present regardless of what the caller passes.
#   The merge() in the resource block combines these defaults with var.tags,
#   so callers can add tags but can't accidentally omit "managed_by".
# -----------------------------------------------------------------------------
locals {
  # Default tags applied to the resource group.
  # merge(local.default_tags, var.tags) means caller tags WIN on conflict —
  # e.g., if the caller passes managed_by = "manual", that overrides "terraform".
  # This is intentional: callers always have final say.
  default_tags = {
    managed_by = "terraform"
  }
}

# -----------------------------------------------------------------------------
# RESOURCE: Azure Resource Group
#
# azurerm_resource_group is the simplest resource in the azurerm provider.
# It maps to the Azure ARM API call: PUT /subscriptions/{id}/resourceGroups/{name}
#
# The resource is named "this" (a Terraform convention for the primary/only
# resource in a module of its type). When there's only one, "this" is cleaner
# than a redundant name like "resource_group".
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location

  # merge() combines two maps, with the second map's values winning on conflict.
  # Result: default_tags + caller's tags, caller wins on duplicate keys.
  tags = merge(local.default_tags, var.tags)

  # ---------------------------------------------------------------------------
  # LIFECYCLE: Prevent accidental destruction
  #
  # WHY prevent_destroy = true?
  #   Deleting a resource group in Azure deletes EVERYTHING inside it — VNets,
  #   databases, AKS clusters, storage accounts, the lot. Terraform's
  #   prevent_destroy causes `terraform destroy` (or any plan that would delete
  #   this resource) to error out with:
  #
  #     "Error: Instance cannot be destroyed"
  #
  #   This forces a deliberate decision: to delete the RG, you must first remove
  #   this block and re-apply. It's a speed bump, not a wall — but the right one.
  #
  # HOW TO OVERRIDE (when you genuinely want to destroy dev):
  #   1. Set prevent_destroy = false in this file (or make it a variable)
  #   2. Run `terragrunt apply` to update the state
  #   3. Run `terragrunt destroy`
  #   Never skip step 2 — Terraform must know the lifecycle changed before destroy.
  # ---------------------------------------------------------------------------
  lifecycle {
    prevent_destroy = true
  }
}
