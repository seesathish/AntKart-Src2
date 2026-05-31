# =============================================================================
# ROOT TERRAGRUNT CONFIGURATION
# File: infrastructure/root.hcl
#
# WHY root.hcl AND NOT terragrunt.hcl?
#
#   Newer versions of Terragrunt emit a deprecation warning if the root
#   configuration file is named "terragrunt.hcl":
#
#     "Using terragrunt.hcl as the root of Terragrunt configurations is an
#      anti-pattern, and no longer recommended."
#
#   The recommended convention is a distinctly named file — root.hcl is the
#   idiomatic choice. This removes the ambiguity between:
#     - root.hcl          : the ONE file that carries shared backend + provider config
#     - terragrunt.hcl    : per-module files that wire a specific module to an environment
#
#   Child modules reference this file explicitly:
#     include "root" { path = find_in_parent_folders("root.hcl") }
#   Passing "root.hcl" by name is required because find_in_parent_folders()
#   defaults to searching for "terragrunt.hcl" — without the explicit argument,
#   it would match the nearest per-module terragrunt.hcl, not this file.
#   See ADR-009 for the full naming rationale.
#
# PURPOSE:
#   This is the single root file that every module-level terragrunt.hcl will
#   include. It centralises two cross-cutting concerns that would otherwise
#   have to be copy-pasted into every module folder:
#
#     1. Remote State Backend  — where Terraform stores its .tfstate files
#     2. Provider Generation   — the azurerm provider block every module needs
#
# HOW IT WORKS:
#   Any terragrunt.hcl deeper in the tree does:
#     include "root" { path = find_in_parent_folders("root.hcl") }
#   Terragrunt walks up the directory tree, finds THIS file, and merges its
#   config into the child. Think of it as inheritance in IaC.
#
# MAINTENANCE:
#   - Subscription ID: update locals.subscription_id if you move subscriptions
#   - Backend:         the tfstate storage account is a one-time pre-created
#                      resource (bootstrapped outside Terraform — see ADR-009)
# =============================================================================

# -----------------------------------------------------------------------------
# ROOT LOCALS
#
# Locals defined here flow into the generated provider block below.
# The subscription ID is not a secret (it's a public Azure identifier), so
# it is safe to hard-code here. Credentials (client_id, client_secret) are
# NEVER here — they come from ARM_ environment variables.
# -----------------------------------------------------------------------------
locals {
  subscription_id = "1a69c45b-82ed-4ec6-972e-c9a5933e6fd0"
}

# -----------------------------------------------------------------------------
# REMOTE STATE BACKEND
#
# WHY remote state instead of local state?
#
#   When Terraform runs, it records everything it created in a state file
#   (terraform.tfstate). If this lives on your laptop:
#     - Teammates can't see it → unsafe concurrent changes
#     - Laptop dies → state lost → Terraform loses track of your infrastructure
#     - Two people run apply at once → corrupted state file
#
#   Remote state in Azure Blob Storage solves all three problems:
#     - Central:   one source of truth for the whole team
#     - Durable:   Blob Storage has 99.999999999% durability (11 nines)
#     - Locked:    Blob Storage leases prevent simultaneous applies
#                  (you'll see "Error acquiring state lock" if someone is
#                   already running apply — that's the safety net working)
#
# WHY path_relative_to_include()?
#
#   If all modules shared a single state file, every plan would show EVERY
#   resource on the platform — slow, and dangerously large blast radius.
#   We give each module its own state file, isolated from all others.
#
#   path_relative_to_include() returns the calling module's path relative to
#   this root file. For example:
#
#     Module at: infrastructure/environments/dev/resource-group/
#     Root at:   infrastructure/
#     Result:    environments/dev/resource-group
#     State key: environments/dev/resource-group/terraform.tfstate
#
#   One container, organised paths, each module independently managed.
#   You can run plan/apply on networking without touching the RG state at all.
#
# WHY generate = { ... } inside remote_state?
#
#   The `generate` block tells Terragrunt to write a backend.tf file into the
#   module directory before running Terraform. This means the module itself
#   never needs a backend block — Terragrunt injects it automatically.
#   The generated file is safe to delete/regenerate (if_exists = overwrite).
# -----------------------------------------------------------------------------
remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # Pre-created storage account for all Terraform state.
    # Created once by hand (or a bootstrap script) — NOT managed by Terraform
    # itself, because you'd have a chicken-and-egg problem: the thing that
    # stores state can't be managed by the thing that needs state.
    resource_group_name  = "rg-antkart-tfstate"
    storage_account_name = "stantkarttfstate2026"
    container_name       = "tfstate"

    # Each module gets a unique state path derived from its folder location.
    # This is the key DRY win: one backend config, per-module isolation.
    key = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# AUTO-GENERATED PROVIDER CONFIGURATION
#
# WHY generate a provider block instead of writing it in each module?
#
#   Every Terraform module needs a provider block. Without Terragrunt, you'd
#   copy this block into every module's main.tf — a maintenance nightmare.
#   With Terragrunt's generate block, we write it once here and Terragrunt
#   injects a provider.tf into each module directory at runtime.
#
# WHY ~> 4.0 for azurerm version?
#
#   The ~> (pessimistic constraint) operator means:
#     >= 4.0.0 AND < 5.0.0
#
#   This gives you:
#     - Stability: locked to major version 4 (no breaking API changes)
#     - Flexibility: automatically picks up bug fixes and minor features
#
#   For production, you might pin to an exact version (= 4.2.0) for
#   reproducibility, but during active development ~> is the right balance.
#
# WHY environment variables for credentials?
#
#   The azurerm provider reads these ARM_ env vars automatically:
#     ARM_CLIENT_ID        → Service Principal's Application (Client) ID
#     ARM_CLIENT_SECRET    → Service Principal's password/secret
#     ARM_TENANT_ID        → Azure Active Directory Tenant ID
#     ARM_SUBSCRIPTION_ID  → Azure Subscription to deploy into
#
#   NEVER put these values in any file that gets committed to Git.
#   Even a private repo today might be public tomorrow, and secrets in
#   Git history are permanent. See DevelopmentGuide.md for how to set them.
#
# NOTE: The subscription_id below is NOT a secret — it's a public Azure
# identifier, like a project ID. Only credentials (client_id, client_secret)
# are secrets.
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    # ==========================================================================
    # AZURE PROVIDER — AUTO-GENERATED BY TERRAGRUNT
    # Source: infrastructure/root.hcl
    #
    # Do NOT edit this file by hand. It is regenerated every time Terragrunt
    # runs. To change the provider configuration, edit infrastructure/root.hcl.
    # ==========================================================================

    terraform {
      # Minimum Terraform version required. We use >= not ~> here because
      # Terraform itself rarely has breaking changes between patch versions.
      required_version = ">= 1.7.0"

      required_providers {
        # hashicorp/azurerm is the official Azure provider for Terraform.
        # It translates Terraform resource blocks into Azure Resource Manager
        # (ARM) REST API calls.
        azurerm = {
          source  = "hashicorp/azurerm"
          version = "~> 4.0"
        }

        # hashicorp/azuread manages Microsoft Entra ID (Azure Active Directory) resources:
        # App Registrations, Service Principals, App Roles, OAuth2 Scopes.
        # Authenticates with the same ARM_ environment variables as azurerm.
        azuread = {
          source  = "hashicorp/azuread"
          version = "~> 3.0"
        }
      }
    }

    # The azurerm provider block tells Terraform how to authenticate and which
    # Azure subscription to target.
    #
    # features {} is required in azurerm 3.x+ even if empty. It enables
    # resource-specific behaviours (e.g., soft-delete for Key Vault, purge
    # protection for recovery vaults). We use defaults for now.
    #
    # Authentication flows from ARM_ environment variables — no secrets here.
    provider "azurerm" {
      features {}
      subscription_id = "${local.subscription_id}"
    }

    # The azuread provider manages Entra ID (Azure AD) resources independently
    # of ARM resources. It reads the same ARM_TENANT_ID, ARM_CLIENT_ID,
    # ARM_CLIENT_SECRET environment variables for Service Principal auth.
    # No additional credentials are needed beyond what azurerm already uses.
    provider "azuread" {}
  EOF
}
