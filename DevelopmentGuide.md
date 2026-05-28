# AntKart Cloud-Native Development Guide

> **This guide is different from `DevTestGuide.md`.**
> `DevTestGuide.md` is for testing the Phase 1 microservices locally with Docker Compose.
> This guide is for building the Phase 2 cloud-native platform on Azure — the act of provisioning infrastructure IS the lesson.

---

## Introduction

You're about to build a production-grade cloud-native e-commerce platform on Azure — not by clicking through the portal, but by writing code that describes infrastructure. Every resource you create in this guide will exist as code in a Git repository, reviewable in a PR, reproducible in any environment, and destroyable with a single command.

This guide is structured in phases. Each phase corresponds to a week of work. You don't have to rush — read the "Why it matters" sections carefully before running commands. The understanding you build in Week 1 carries everything that follows.

**Who is this for?** Developers who know how to build .NET applications and want to understand how those applications get deployed at scale in Azure. You don't need prior Terraform experience — this guide explains every concept as it's introduced.

---

## Prerequisites (set up once)

Before starting Section 1, make sure you have these installed and working:

| Tool | Version | Check | Install |
|------|---------|-------|---------|
| Azure CLI | ≥ 2.60 | `az --version` | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| Terraform | ≥ 1.7.0 | `terraform version` | https://developer.hashicorp.com/terraform/install |
| Terragrunt | ≥ 0.55.0 | `terragrunt --version` | https://terragrunt.gruntwork.io/docs/getting-started/install/ |
| Git | any | `git --version` | pre-installed on most machines |

Verify you can log in to Azure:
```powershell
az login
az account show
```

You should see your subscription details. If you see the wrong subscription:
```powershell
az account set --subscription "1a69c45b-82ed-4ec6-972e-c9a5933e6fd0"
```

---

## Section 1: Provisioning AntKart's Azure Foundation

### What you're about to do

In this section, you'll use Terraform and Terragrunt to provision two foundational Azure resources: a **Resource Group** (the logical container for all AntKart resources in dev) and a **Virtual Network** with three subnets (the private network AKS, databases, and the API gateway will live inside). These two resources are the bedrock — everything in the remaining sections builds on top of them.

### Why it matters

**Why Infrastructure as Code instead of clicking in the Azure portal?**

The Azure portal is a great exploration tool. But every click you make in the portal creates a resource that exists only in Azure — it's not in your Git repository, it can't be reviewed in a pull request, it can't be replicated exactly to staging and prod, and it can't be recovered if someone accidentally deletes it. A month from now, no one (including you) will remember exactly what settings you chose.

With Terraform, your infrastructure is code. It has the same properties as application code:
- **Version controlled** — every change is a commit with a message and a reviewer
- **Reproducible** — `terraform apply` in staging creates exactly what it creates in dev
- **Reviewable** — infrastructure changes go through the same PR process as code changes
- **Self-documenting** — reading the `.tf` files tells you exactly what exists in Azure

**Why Terragrunt on top of Terraform?**

Terraform is excellent, but it has one structural weakness: every module needs its own backend configuration and provider block. Without Terragrunt, you'd copy these blocks into every folder. With Terragrunt's `include` pattern, you write backend and provider config once in `infrastructure/terragrunt.hcl` and every module inherits it automatically — the same DRY principle as a base class in C#.

Terragrunt also gives you the `dependency` block — a way for modules to read each other's outputs without sharing state files. The networking module reads the resource group name from the resource group module's outputs, rather than hard-coding it.

**Why remote state in Azure Blob Storage?**

Terraform's state file (`terraform.tfstate`) is the source of truth for what exists in Azure. It maps your code to real Azure resource IDs. If it lives on your laptop:
- Your teammates can't make safe changes (they don't have the state)
- A laptop failure loses the state → Terraform can no longer manage the resources
- Two engineers running `apply` at the same time → corrupted state

Azure Blob Storage solves all three: centralised, durable, and with blob lease-based locking so only one apply runs at a time.

---

### Step 1.1 — Set your credentials

Terraform authenticates to Azure using a Service Principal. Think of a Service Principal as a dedicated identity for automated tools — like a service account in Active Directory. The credentials are passed via environment variables so they never touch any file.

Open a PowerShell session and run:

```powershell
# Ask your architect for the ARM_CLIENT_ID and ARM_CLIENT_SECRET values.
# These correspond to the 'antkart-terraform-sp' Service Principal.
# NEVER commit these values to Git.

$env:ARM_CLIENT_ID       = "<service-principal-client-id>"
$env:ARM_CLIENT_SECRET   = "<service-principal-client-secret>"
$env:ARM_TENANT_ID       = "4cacc56a-0d38-46c4-ba20-429d51d7b449"
$env:ARM_SUBSCRIPTION_ID = "1a69c45b-82ed-4ec6-972e-c9a5933e6fd0"
```

Verify they're set (the values will be masked in some terminals):
```powershell
echo "CLIENT_ID:   $env:ARM_CLIENT_ID"
echo "TENANT_ID:   $env:ARM_TENANT_ID"
echo "SUB_ID:      $env:ARM_SUBSCRIPTION_ID"
```

> **Important:** These environment variables are session-scoped. If you close PowerShell and re-open it, you'll need to set them again. Consider creating a local script file (NOT committed to Git — add it to `.gitignore`) that sets them for your machine.

---

### Step 1.2 — Deploy the Resource Group

Navigate to the dev resource-group module:

```powershell
cd infrastructure/environments/dev/resource-group
```

**Initialise Terraform:**
```powershell
terragrunt init
```

Expected output:
```
Initializing the backend...
Successfully configured the backend "azurerm"!

Initializing provider plugins...
- Finding hashicorp/azurerm versions matching "~> 4.0"...
- Installing hashicorp/azurerm v4.x.x...
- Installed hashicorp/azurerm v4.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

> **What just happened?**
> Terragrunt read `infrastructure/terragrunt.hcl` and injected two files into a local cache:
> - `backend.tf` — tells Terraform to store state in Azure Blob Storage under key `environments/dev/resource-group/terraform.tfstate`
> - `provider.tf` — configures the azurerm provider with your subscription ID
>
> Then it ran `terraform init`, which downloaded the azurerm provider plugin (~200MB on first run — subsequent runs use the cache). The remote state backend in Azure Blob Storage was configured and verified.

**Preview the changes:**
```powershell
terragrunt plan
```

Expected output:
```
Terraform will perform the following actions:

  # azurerm_resource_group.this will be created
  + resource "azurerm_resource_group" "this" {
      + id       = (known after apply)
      + location = "eastus"
      + name     = "rg-antkart-dev-eastus"
      + tags     = {
          + "environment" = "dev"
          + "managed_by"  = "terraform"
          + "owner"       = "sathish"
          + "project"     = "antkart"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

> **What just happened?**
> Terraform compared your desired state (the `.tf` files) against the current state (an empty state file — nothing has been created yet). The `+` sign means "this resource will be created." The `(known after apply)` values are IDs that Azure generates — Terraform doesn't know them until after creation.
>
> **`plan` is read-only.** It makes no changes to Azure. Think of it as a dry run — you're reviewing what's about to happen before committing.

**Apply the changes:**
```powershell
terragrunt apply
```

Terraform will show the plan again and prompt:
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Type `yes` and press Enter.

Expected output:
```
azurerm_resource_group.this: Creating...
azurerm_resource_group.this: Creation complete after 3s
  [id=/subscriptions/1a69c45b-82ed-4ec6-972e-c9a5933e6fd0/resourceGroups/rg-antkart-dev-eastus]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
id       = "/subscriptions/1a69c45b.../resourceGroups/rg-antkart-dev-eastus"
location = "eastus"
name     = "rg-antkart-dev-eastus"
```

> **What just happened?**
> Terraform called the Azure Resource Manager REST API to create the resource group. The result was saved to the state file in Azure Blob Storage. The `Outputs:` section shows the values that other modules (networking, AKS, etc.) will read via the dependency block.

---

### Step 1.3 — Deploy the Virtual Network

Navigate to the dev networking module:
```powershell
cd ../networking
```

```powershell
terragrunt init
```

```powershell
terragrunt plan
```

Expected output (8 resources):
```
  + azurerm_virtual_network.this                                will be created
  + azurerm_subnet.aks                                          will be created
  + azurerm_subnet.pe                                           will be created
  + azurerm_subnet.appgw                                        will be created
  + azurerm_network_security_group.aks                          will be created
  + azurerm_network_security_group.pe                           will be created
  + azurerm_subnet_network_security_group_association.aks       will be created
  + azurerm_subnet_network_security_group_association.pe        will be created

Plan: 8 to add, 0 to change, 0 to destroy.
```

> **What just happened?**
> Notice that Terraform resolved the resource group name by reading the remote state from Step 1.2 (via the `dependency.resource_group` block in `networking/terragrunt.hcl`). It didn't need you to type the RG name — it read it from the output the resource-group module stored in Blob Storage.

```powershell
terragrunt apply
```

Expected output:
```
azurerm_virtual_network.this: Creating...
azurerm_subnet.aks: Creating...
azurerm_subnet.pe: Creating...
azurerm_subnet.appgw: Creating...
azurerm_network_security_group.aks: Creating...
azurerm_network_security_group.pe: Creating...
azurerm_subnet_network_security_group_association.aks: Creating...
azurerm_subnet_network_security_group_association.pe: Creating...

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:
aks_subnet_id  = "/subscriptions/.../subnets/snet-aks-antkart-dev"
appgw_subnet_id = "/subscriptions/.../subnets/snet-appgw-antkart-dev"
pe_subnet_id   = "/subscriptions/.../subnets/snet-pe-antkart-dev"
vnet_id        = "/subscriptions/.../virtualNetworks/vnet-antkart-dev"
vnet_name      = "vnet-antkart-dev"
```

> **What just happened?**
> Eight Azure resources were provisioned in parallel where dependencies allowed: the VNet was created first (subnets depend on it), then the three subnets and two NSGs in parallel, then the two NSG-subnet associations last (they depend on both subnets and NSGs existing). Terraform's dependency graph handled the ordering automatically.

---

### Step 1.4 — Verify in the Azure Portal

1. Go to https://portal.azure.com and sign in.
2. Search for **"Resource groups"** at the top — click it.
3. Find **rg-antkart-dev-eastus** in the list.
4. Click into it. You should see these resources:
   - `vnet-antkart-dev` (Virtual network)
   - `nsg-aks-antkart-dev` (Network security group)
   - `nsg-pe-antkart-dev` (Network security group)
5. Click `vnet-antkart-dev` → **Subnets** (left menu).
   You should see:
   | Name | Address range |
   |------|--------------|
   | snet-aks-antkart-dev | 10.0.0.0/22 |
   | snet-pe-antkart-dev | 10.0.4.0/24 |
   | snet-appgw-antkart-dev | 10.0.5.0/27 |
6. Click `nsg-aks-antkart-dev` → **Inbound security rules** (left menu).
   You should see your three rules: allow-vnet-inbound, allow-azure-load-balancer-inbound, deny-all-inbound.
7. Click the **Tags** tab on the resource group. You should see: environment=dev, project=antkart, managed_by=terraform, owner=sathish.

If everything looks right — you've just provisioned real Azure infrastructure with code. Well done.

---

### Step 1.5 — Try this experiment

This exercise teaches you how Terraform detects and handles change.

Open `infrastructure/environments/dev/env.hcl` and change the owner tag:

```hcl
owner = "your-name"   # change from "sathish" to your name
```

Save the file, then run:

```powershell
cd ../resource-group
terragrunt plan
```

You should see:

```
~ resource "azurerm_resource_group" "this" {
    name     = "rg-antkart-dev-eastus"
    location = "eastus"
  ~ tags = {
      ~ "owner" = "sathish" -> "your-name"
        # (3 unchanged elements hidden)
    }
}

Plan: 0 to add, 1 to change, 0 to destroy.
```

Terraform is telling you: "I will update exactly one attribute of one resource. Nothing will be created or destroyed."

```powershell
terragrunt apply
```

Watch it apply in under 2 seconds. Check the Tags tab in the Azure portal — the owner tag updates immediately.

**Now try for networking:**
```powershell
cd ../networking
terragrunt plan
```

You should see the tag change propagating to all networking resources too (VNet and NSGs) since they all inherit `common_tags` from `env.hcl`.

> **What this teaches:**
> Terraform is **declarative** — you describe the desired end state, and Terraform figures out the minimum set of changes needed to get there. It doesn't "re-create" resources on every apply. It computes a diff between desired state and current state, just like `git diff` shows what changed in your code.

Change the owner back to "sathish" when you're done.

---

### Step 1.6 — Troubleshooting

| Problem | Symptoms | Fix |
|---------|----------|-----|
| **Auth failure** | `Error: Error building ARM Client: client_id must be set` | Re-run the `$env:ARM_*` PowerShell commands — they don't persist when you close the terminal |
| **State lock** | `Error: Error acquiring the state lock` | Another apply is running (or a previous one crashed). Wait 2 minutes and retry. If still locked: `terragrunt force-unlock <lock-id>` (the lock ID is in the error message) |
| **Subscription not found** | `Error: The subscription ... was not found` | Check `$env:ARM_SUBSCRIPTION_ID` is set correctly and the SP has Contributor access to it |
| **Backend not initialised** | `Error: Backend initialization required` | Run `terragrunt init` before `plan` or `apply` |
| **State storage not found** | `ResourceGroupNotFound` during init | The `rg-antkart-tfstate` resource group or `stantkarttfstate2026` storage account doesn't exist. Ask your architect — these are bootstrapped once outside Terraform |
| **Provider version mismatch** | `Error: Unsupported argument` on a resource | Your azurerm provider version is too old. Delete `.terragrunt-cache/` and run `terragrunt init` again |
| **SP insufficient permissions** | `AuthorizationFailed` during apply | The Service Principal needs `Contributor` role on the subscription. Ask your architect to check `az role assignment list --assignee <client-id>` |

---

### What's next — Section 2: Container Registry and Key Vault

In Section 2 you'll provision:

- **Azure Container Registry (ACR)** — where your Docker images live in Azure. When GitHub Actions builds your microservices, it pushes images here. AKS pulls from here to deploy.
- **Azure Key Vault** — where your secrets live. Razorpay keys, database passwords, SMTP credentials — all move out of `appsettings.json` and `docker-compose.yml` into Key Vault. AKS retrieves them at pod startup via the Secrets Store CSI Driver.

By the end of Section 2, you'll have a container registry that AKS can pull from and a vault that stores every secret AntKart needs.

---

## Appendix A — Deploying all dev modules at once

Once you're comfortable with the individual steps, Terragrunt's `run-all` command lets you deploy everything in one command from the environment root:

```powershell
cd infrastructure/environments/dev
terragrunt run-all init
terragrunt run-all plan
terragrunt run-all apply
```

Terragrunt reads the `dependency` blocks across all modules and builds a dependency graph, then deploys in the correct order (resource-group → networking → everything that depends on networking).

> Use `run-all` once you trust the individual modules. When learning or debugging, run each module individually so you can see exactly what's happening.

## Appendix B — Destroying the dev environment

To tear down dev resources (e.g., to save costs outside of active development):

```powershell
cd infrastructure/environments/dev

# Destroy in reverse dependency order
cd networking       && terragrunt destroy && cd ..
cd resource-group   && terragrunt destroy && cd ..
```

> **Note:** The resource-group module has `prevent_destroy = true`. To destroy it:
> 1. Edit `infrastructure/modules/resource-group/main.tf` — set `prevent_destroy = false`
> 2. Run `terragrunt apply` in the resource-group folder (updates the lifecycle in state)
> 3. Run `terragrunt destroy`
> 4. Set it back to `true` and commit

## Appendix C — Checking Terraform state

To see what Terraform currently knows about a deployed resource:

```powershell
cd infrastructure/environments/dev/resource-group
terragrunt state list
# Output: azurerm_resource_group.this

terragrunt state show azurerm_resource_group.this
# Output: Full resource attributes as Terraform sees them
```

This is useful for debugging discrepancies between what you see in Azure and what Terraform thinks exists.
