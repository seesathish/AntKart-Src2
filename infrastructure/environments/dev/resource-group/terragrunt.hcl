# =============================================================================
# DEV RESOURCE GROUP — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/resource-group/terragrunt.hcl
#
# PURPOSE:
#   Wires the reusable resource-group MODULE to the dev ENVIRONMENT.
#   This file answers: "Which module? With what inputs? For which environment?"
#
# SEPARATION OF CONCERNS:
#   ┌─────────────────────────────────────────────────────────────┐
#   │ infrastructure/modules/resource-group/   ← WHAT to create  │
#   │   (reusable, environment-agnostic code)                     │
#   │                                                             │
#   │ infrastructure/environments/dev/env.hcl  ← configuration   │
#   │   (dev-specific values: region, tags, naming prefix)       │
#   │                                                             │
#   │ THIS FILE                                ← wires them       │
#   │   (points module at source, passes env values as inputs)    │
#   └─────────────────────────────────────────────────────────────┘
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/resource-group
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
# =============================================================================

# -----------------------------------------------------------------------------
# INCLUDE ROOT — Inherit backend and provider configuration
#
# find_in_parent_folders() walks up the directory tree looking for a file
# named terragrunt.hcl. Starting from this file's directory:
#   environments/dev/resource-group/ → environments/dev/ → environments/ → infrastructure/
#
# It finds infrastructure/terragrunt.hcl which contains:
#   - The azurerm remote backend pointing to Azure Blob Storage
#   - The generate "provider" block that creates provider.tf
#
# merge_strategy defaults to "deep_merge" — the root's remote_state and
# generate blocks are merged into this module's config.
# -----------------------------------------------------------------------------
include "root" {
  path = find_in_parent_folders()
}

# -----------------------------------------------------------------------------
# INCLUDE ENV — Read dev-specific configuration
#
# find_in_parent_folders("env.hcl") finds the nearest env.hcl walking up:
#   environments/dev/resource-group/ → environments/dev/  ← found: env.hcl
#
# expose = true:
#   Makes this file's locals accessible as include.env.locals.*
#   Without expose, the file is merged but locals aren't directly readable.
#
# merge_strategy = "no_merge":
#   We only want to READ env.hcl's locals — not merge its inputs (it has none).
#   "no_merge" is explicit: "include this for reading, not for merging config."
# -----------------------------------------------------------------------------
include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

# -----------------------------------------------------------------------------
# MODULE SOURCE
#
# The `source` path is relative to THIS file's location.
# ../../../modules/resource-group resolves to:
#   dev/resource-group/ → dev/ → environments/ → infrastructure/modules/resource-group/
#
# Terragrunt copies the module source to a temporary .terragrunt-cache folder
# and runs Terraform from there. The generated backend.tf and provider.tf are
# injected into that cache folder, not into the module source.
# -----------------------------------------------------------------------------
terraform {
  source = "../../../modules/resource-group"
}

# -----------------------------------------------------------------------------
# INPUTS — Environment-specific values passed to the module's variables
#
# These become the module's var.name, var.location, var.tags.
# We build all values from env.hcl locals so there's no duplication:
#   Change environment name in env.hcl → all resource names update automatically.
#
# NAMING: rg-antkart-dev-eastus follows Azure CAF convention:
#   rg  = resource type abbreviation (Resource Group)
#   antkart = project/workload name (naming_prefix)
#   dev     = environment
#   eastus  = region
# -----------------------------------------------------------------------------
inputs = {
  name     = "rg-${include.env.locals.naming_prefix}-${include.env.locals.environment}-${include.env.locals.location}"
  location = include.env.locals.location
  tags     = include.env.locals.common_tags
}
