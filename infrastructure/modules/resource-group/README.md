# Module: resource-group

Creates an Azure Resource Group — the logical container that holds all AntKart
resources in a given environment. Every Azure resource must belong to exactly
one resource group.

## What this module does

1. Creates the resource group at the specified location
2. Applies a merged tag set (module defaults + caller-provided tags)
3. Protects against accidental deletion via `prevent_destroy = true`
4. Exposes `id`, `name`, and `location` for downstream modules to consume

## Why a module for something this simple?

A resource group is only one resource — so why wrap it in a module? Because:

- **Naming conventions** are enforced once here, not in every environment config
- **Tag standards** (the `managed_by = "terraform"` default) are always applied
- **Lifecycle protection** lives in one place — you can't forget it in prod
- **Outputs** give downstream modules a clean dependency interface

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name` | string | yes | Resource group name. Convention: `rg-<project>-<environment>-<region>` |
| `location` | string | yes | Azure region (e.g., `eastus`, `centralindia`) |
| `tags` | map(string) | no | Tags to apply. Merged with defaults; caller wins on conflicts |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Full Azure Resource ID of the resource group |
| `name` | Resource group name (reference in child modules) |
| `location` | Azure region |

## Example usage (from a terragrunt.hcl)

```hcl
terraform {
  source = "../../../modules/resource-group"
}

inputs = {
  name     = "rg-antkart-dev-eastus"
  location = "eastus"
  tags = {
    environment = "dev"
    project     = "antkart"
    managed_by  = "terraform"
    owner       = "sathish"
  }
}
```

## Important: prevent_destroy

This module has `prevent_destroy = true` on the resource group. This means
`terraform destroy` will fail with an error if it would delete the RG.

To destroy a dev environment:
1. Set `prevent_destroy = false` in `main.tf`
2. Run `terragrunt apply` to update the lifecycle in state
3. Run `terragrunt destroy`

This is intentional — deleting a resource group deletes **everything** inside it.
