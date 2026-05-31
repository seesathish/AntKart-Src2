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

> ### ⚠️ Critical Discipline: The Portal is Read-Only
>
> Once Terraform manages a resource, **never create, modify, or delete it from the Azure portal.** Use the portal only to *view* what Terraform has built.
>
> **Why this matters — "drift":**
> When you change something in the portal, Terraform doesn't know about it. The portal and Terraform's state file now disagree about what exists. This is called drift. On the next `terragrunt plan`, Terraform will try to undo your portal change — because as far as it's concerned, the desired state is still what's in the code. If you deleted a resource from the portal, the next `apply` will try to recreate it. If you modified one, Terraform will overwrite your change. Either way, the portal edit was wasted work.
>
> **The correct workflows:**
> | Goal | Wrong | Right |
> |------|-------|-------|
> | Change a tag | Edit in portal | Edit `env.hcl`, run `terragrunt apply` |
> | Delete a resource | Delete in portal | Run `terragrunt destroy` |
> | Add a new resource | Create in portal | Write it in `.tf`, run `terragrunt apply` |
> | Investigate an issue | ✅ Portal is fine | — (read-only is always OK) |
>
> **What happens if you break the rule:**
> If a resource is deleted from the portal, Terraform's state still records it as existing. The next `terragrunt plan` will show an error or try to recreate it in a partially-configured state. Fix by running `terragrunt state rm <resource>` to remove it from state (tells Terraform to forget about it), then let `apply` recreate it cleanly.
>
> **The habit that makes this easy:**
> Treat `.tf` and `.hcl` files the same way you treat application source code. If it's not in Git, it doesn't exist. Anything you type into the portal is temporary and will be overwritten.

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

### Step 1.5 — The Destroy/Recreate Cycle — Your Cost-Control Superpower

This is the most important habit you'll build on this platform.

**Why it matters:**
When we add AKS in Section 3, the cluster will cost roughly **$5 per day** in Azure compute charges — even when you're not using it. Networking resources (VNet, subnets, NSGs) are **free**. The resource group itself is free.

The professional habit is: **destroy AKS at the end of every work session. Recreate it at the start of the next one.**

Terraform makes this safe because it has perfect memory. After a destroy, running `apply` again rebuilds everything identically from the code. You're not losing any configuration — just releasing the hourly compute charge.

**Practice the cycle now with networking (zero cost, zero risk):**

```powershell
# Step 1: Confirm what you have
cd infrastructure/environments/dev/networking
terragrunt state list
```

Expected output:
```
azurerm_network_security_group.aks
azurerm_network_security_group.pe
azurerm_subnet.aks
azurerm_subnet.appgw
azurerm_subnet.pe
azurerm_subnet_network_security_group_association.aks
azurerm_subnet_network_security_group_association.pe
azurerm_virtual_network.this
```

```powershell
# Step 2: Destroy the networking resources
terragrunt destroy
```

Terraform will show a plan listing all 8 resources to be destroyed. Type `yes` when prompted.

Expected output:
```
azurerm_subnet_network_security_group_association.aks: Destroying...
azurerm_subnet_network_security_group_association.pe: Destroying...
azurerm_subnet.aks: Destroying...
azurerm_subnet.pe: Destroying...
azurerm_subnet.appgw: Destroying...
azurerm_network_security_group.aks: Destroying...
azurerm_network_security_group.pe: Destroying...
azurerm_virtual_network.this: Destroying...

Destroy complete! Resources: 8 destroyed.
```

Go to the Azure Portal — the VNet and NSGs are gone from the resource group. The resource group itself is still there (protected by `prevent_destroy = true`).

```powershell
# Step 3: Recreate from code
terragrunt apply
```

Eight resources are recreated in about 90 seconds. The VNet, subnets, and NSG rules are identical to what existed before — all driven from the same code.

> **What this teaches:**
> Infrastructure created by code is **disposable and reproducible**. You can tear it down and rebuild it with confidence because the source of truth is the `.tf` files in Git, not the live resources in Azure. This is fundamentally different from manually-created infrastructure, where destroying something means losing knowledge of how to recreate it.

**The cost-control workflow for Section 3+ (when AKS is running):**
```powershell
# Start of work session — bring everything up
cd infrastructure/environments/dev
terragrunt run-all apply

# End of work session — destroy only the expensive bits
cd aks && terragrunt destroy && cd ..
# networking and RG stay (they're free)
```

> **Side observation:** The resource group survives the networking destroy because it lives in a separate module with its own state. But even if you tried running `terragrunt destroy` from the resource group module directory, Terraform would refuse — see "When Terraform Refuses" just ahead for why that refusal is the right design.

---

### Step 1.6 — When Terraform Refuses — The `prevent_destroy` Guardrail

If you tried running `terragrunt destroy` from the resource group module directory, Terraform refused with this error:

```
Error: Instance cannot be destroyed

  on main.tf line 56, in resource "azurerm_resource_group" "this":
  56: resource "azurerm_resource_group" "this" {

Resource azurerm_resource_group.this has lifecycle.prevent_destroy set, but
the plan calls for this resource to be destroyed.
```

This is not a bug. It's a deliberate safety net.

**What's causing it**

Open [infrastructure/modules/resource-group/main.tf](infrastructure/modules/resource-group/main.tf). Near the bottom of the resource block:

```hcl
resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = merge(local.default_tags, var.tags)

  lifecycle {
    prevent_destroy = true   # <-- the guardrail
  }
}
```

The `lifecycle` block tells Terraform: "If any plan would destroy this resource — through any command, any script, any pipeline — refuse and error out." It doesn't matter who runs it or what flags they pass. The protection is baked into the module itself.

**Why the resource group specifically**

A resource group in Azure is a container. Destroying it destroys *every resource inside it*. Once AKS, Cosmos DB, Service Bus, Key Vault, and your databases all live inside `rg-antkart-dev-eastus`, a single accidental `terragrunt destroy` from the wrong directory would wipe the entire environment — including all data — in under five minutes. The `prevent_destroy` flag makes that mistake impossible without an explicit, deliberate code change.

**Which resources should have this guardrail**

| Resource | Guardrail? | Why |
|----------|-----------|-----|
| Resource group | Yes | Destroys all child resources — catastrophic blast radius |
| Key Vault | Yes | Has soft-delete + purge protection; rebuilding loses key history |
| Cosmos DB | Yes | Contains business data |
| Storage account (with data) | Yes | Data loss |
| Production AKS | Yes | Rebuilds take time; node IPs and identities change |
| Virtual Network | Optional | Free to rebuild, but breaks all dependent peerings |
| NSG | No | Pure configuration — disposable and instant to recreate |
| ACR | Optional | Depends on whether you want to retain pushed images |
| Log Analytics Workspace | Yes in prod | Historical telemetry lives here |

**How to genuinely destroy a protected resource**

If you ever truly need to destroy something with `prevent_destroy = true`, the process is intentionally awkward:

1. Open the module's `main.tf` and comment out the `prevent_destroy` line:
   ```hcl
   lifecycle {
     # prevent_destroy = true   ← commented out
   }
   ```
2. Run `terragrunt apply` — this changes nothing in Azure, but it updates Terraform's state so it now knows the protection is gone.
3. Run `terragrunt destroy` — now permitted.
4. Restore `prevent_destroy = true` and re-apply if the resource will be recreated.

Step 2 is not optional. If you skip it and go straight to destroy, Terraform may still refuse because it reads the lifecycle flag from its cache. You must apply the change first.

This ceremony exists so you can't destroy accidentally. In a PR-based workflow, removing a `prevent_destroy = true` line appears as a code diff — one that should trigger a review comment: *"Why are we removing this protection? What's the rollback plan?"*

**What this means for the destroy/recreate cycle**

The cycle you practiced in Step 1.5 is designed for "low-stakes, free, easily rebuilt" resources — perfect for networking (VNet, subnets, NSGs cost nothing and rebuild in 90 seconds). It is **not** designed for resource groups, Key Vaults, or anything holding data.

The `prevent_destroy` guardrail on the resource group is the system separating "safe to destroy routinely" from "only destroy with a deliberate decision." Networking lives on one side of that boundary. The resource group lives on the other.

**The architect mindset**

As you design each new module, ask one question for every resource: "What's the cost of accidentally destroying this?" If the answer is *data loss* or *hours of rebuild work*, add `prevent_destroy = true`. If the answer is *30 seconds and zero dollars*, leave it disposable. That single judgment call is one of the most consequential decisions in IaC design.

> **Optional — check the pattern as we build:** Browse through `infrastructure/modules/` as each new module is added (ACR, Key Vault, Cosmos DB, AKS). Notice which ones include `prevent_destroy` and which don't. The pattern should match the table above. If you ever spot a mismatch — say, Key Vault without the guardrail — that's a security review finding worth flagging before any production deployment.

---

### Step 1.7 — Seeing Terraform's Memory — Inspecting Remote State

Terraform's state file is the JSON document that records everything it created. It lives in Azure Blob Storage at `stantkarttfstate2026/tfstate/environments/dev/resource-group/terraform.tfstate`. You can inspect it without downloading it:

```powershell
cd infrastructure/environments/dev/resource-group

# List all resources Terraform is tracking
terragrunt state list
```

Expected output:
```
azurerm_resource_group.this
```

```powershell
# Show all recorded attributes of the resource group
terragrunt state show azurerm_resource_group.this
```

Expected output (abbreviated):
```
# azurerm_resource_group.this:
resource "azurerm_resource_group" "this" {
    id       = "/subscriptions/1a69c45b-82ed-4ec6-972e-c9a5933e6fd0/resourceGroups/rg-antkart-dev-eastus"
    location = "eastus"
    name     = "rg-antkart-dev-eastus"
    tags     = {
        "environment" = "dev"
        "managed_by"  = "terraform"
        "owner"       = "sathish"
        "project"     = "antkart"
    }
}
```

This is Terraform's snapshot of the resource. When you run `plan`, Terraform compares this snapshot against your `.tf` files and against the live Azure state. A three-way diff:
- **Code vs state** → what you want to change
- **State vs live** → whether someone changed Azure outside of Terraform (drift)

**Look at the state file directly:**

You can download and inspect the raw JSON from the Azure Portal:
1. Go to Storage Accounts → `stantkarttfstate2026` → Containers → `tfstate`
2. Navigate to `environments/dev/resource-group/terraform.tfstate`
3. Click the file → Download

The JSON contains:
```json
{
  "version": 4,
  "terraform_version": "1.x.x",
  "serial": 3,
  "lineage": "a1b2c3d4-...",
  "resources": [
    {
      "type": "azurerm_resource_group",
      "name": "this",
      "instances": [
        {
          "attributes": {
            "id": "/subscriptions/.../resourceGroups/rg-antkart-dev-eastus",
            "name": "rg-antkart-dev-eastus",
            "location": "eastus",
            "tags": { ... }
          }
        }
      ]
    }
  ]
}
```

Key fields to understand:
- **`serial`**: Increments with every apply. If two people apply simultaneously, their serials conflict — the second apply is rejected (this is how locking works).
- **`lineage`**: A unique identifier for this state file's history. Prevents accidentally merging state from two different environments.
- **`instances[].attributes.id`**: The Azure Resource Manager ID — the permanent address of the resource. This changes if you destroy and recreate the resource, even if the name stays the same.

> **Why does the ID change on recreate?**
> Azure assigns a new internal ID every time a resource is created. The *name* you choose stays the same (because you wrote it in code), but the *identity* is new. This is important for anything that holds a reference to the old ID — a role assignment or a dependency in another module would need to be updated.

---

### Step 1.8 — Try these experiments

**Experiment 1 — In-place update (the `~` symbol)**

This shows how Terraform detects and applies changes without recreating resources.

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

**Experiment 2 — IDs change on destroy/recreate**

This shows that resource identity (the Azure ID) is not the same as resource name.

Run the networking destroy/recreate cycle from Step 1.5:
```powershell
cd infrastructure/environments/dev/networking
terragrunt destroy
terragrunt apply
```

Now check the VNet ID:
```powershell
terragrunt state show azurerm_virtual_network.this
```

Compare the `id` field to what you saw in Step 1.7. You'll see it has changed:
```
# Before destroy/recreate:
id = "/subscriptions/.../virtualNetworks/vnet-antkart-dev"
      └── ends with: ...providers/Microsoft.Network/virtualNetworks/vnet-antkart-dev

# After recreate — same name, DIFFERENT internal ID:
id = "/subscriptions/.../virtualNetworks/vnet-antkart-dev"
     └── the path looks identical but the underlying resource record in Azure is new
```

In practice, the ARM ID path looks the same because it's derived from the resource name and resource group — but Azure has replaced the old resource with a new one. Any resource that stored the old ID as a reference (a role assignment, a Private DNS zone link) would be broken. This is why `prevent_destroy = true` on the resource group is important — accidentally destroying it would force every dependent resource to be recreated and every external reference to be updated.

---

**Experiment 3 — Plan symbols: `~` vs `-/+` vs `+`**

Terraform uses three symbols in plan output. Understanding them prevents surprises:

| Symbol | Meaning | Cost |
|--------|---------|------|
| `+` | Resource will be **created** | New Azure resource |
| `-` | Resource will be **destroyed** | Azure resource deleted |
| `~` | Resource will be **updated in place** | No recreation, just attribute change |
| `-/+` | Resource will be **destroyed and recreated** | Brief downtime possible |

To see the difference between `~` and `-/+`: open `infrastructure/environments/dev/networking/terragrunt.hcl` and change the VNet address space from `10.0.0.0/16` to `10.0.0.0/8`:

```hcl
address_space = ["10.0.0.0/8"]   # was /16
```

Run:
```powershell
cd infrastructure/environments/dev/networking
terragrunt plan
```

You'll see `-/+` for the VNet and all subnets:
```
# azurerm_virtual_network.this must be replaced
-/+ resource "azurerm_virtual_network" "this" {
  ~ address_space = ["10.0.0.0/16"] -> ["10.0.0.0/8"] # forces replacement
```

The `# forces replacement` note explains why. Changing a VNet's address space requires Azure to delete and recreate it. Compare this to changing a tag (`~` only — Azure can update the tag metadata without touching the network configuration).

**Do not apply this change.** Revert the address_space back to `"10.${include.env.locals.network_octet}.0.0/16"` and discard.

> **What this teaches:**
> Before every `apply`, always read the full plan output. Pay special attention to `-/+` lines — they mean your change has a destructive side effect. In production, that could mean downtime. In dev, it's fine, but you should understand why it's happening.

---

### Step 1.9 — Troubleshooting

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

---

## Section 2: Container Registry, Secrets, and Observability Foundation

### What you're about to do

In this section you'll provision four Azure resources that every subsequent week
depends on:

1. **Azure Container Registry (ACR)** — the private Docker registry for all AntKart images
2. **Azure Key Vault** — the central secrets vault; no more credentials in appsettings.json
3. **Azure Log Analytics Workspace** — the telemetry data lake for the entire platform
4. **Azure Application Insights** — the APM layer; distributed traces across all 8 services

By the end of this section, you'll have a registry AKS can pull from, a vault that
holds every secret, and a telemetry foundation that will light up the moment microservices
start sending data.

---

### Why it matters

**Why a container registry?**

Docker Compose runs images from Docker Hub or builds them locally. AKS cannot do either.
AKS pulls images at pod startup — it needs them in a registry it can reach. ACR is
co-located with Azure (fast pull, no egress charge) and integrates with AKS via managed
identity (no passwords to manage). Every microservice image you build in CI/CD will be
pushed here before AKS can run it.

**Why a secrets vault?**

Right now, Razorpay keys, the Keycloak client secret, database passwords, and SMTP
credentials live in `appsettings.json` and `docker-compose.yml`. That's acceptable for
Phase 1 (local, private, no production data). It is not acceptable for Phase 2, where:
- The repo might be shared or made public
- Multiple developers and pipelines need access to the same credentials
- Credentials must be rotatable without redeploying the application

Key Vault solves all three: secrets live in one place, access is RBAC-controlled, and
rotating a secret doesn't require a new Docker image.

**Why observability this early?**

The worst time to add observability is after something breaks in production. Setting up
Log Analytics and App Insights now means every microservice that connects to the cluster
gets distributed tracing, exception tracking, and performance baselines from the first
request. When something goes wrong in Week 5 (and it will), you'll have 3 weeks of
telemetry to look at.

---

### The four services — brief orientation

**Azure Container Registry (ACR)**

A private Docker registry hosted in Azure. Images are pushed by CI/CD pipelines and
pulled by AKS node pools. AKS authenticates using the node's managed identity with the
`AcrPull` RBAC role — no passwords, no stored credentials. We start on the Basic SKU
(~$5/month) and upgrade to Premium when private networking is required.

**Azure Key Vault**

A managed secrets store. Secrets are key-value pairs accessed via HTTPS. Authorization
uses Azure RBAC — the deploying Service Principal gets `Key Vault Secrets Officer`
(manage secrets) and AKS nodes will get `Key Vault Secrets User` (read-only) when the
cluster is provisioned. Soft-delete and purge protection prevent accidental permanent
deletion. Effectively free for this workload (~$0.03 per 10,000 operations).

**Azure Log Analytics Workspace**

A managed data store for structured log and metric data. All observability signals for
the AntKart platform flow here: App Insights traces, AKS Container Insights (pod/node
metrics), NSG flow logs, and Key Vault audit logs. One workspace covers all 8 services
in a single KQL query. The first 5 GB/month is free — dev AntKart traffic stays well
within that.

**Azure Application Insights**

The APM layer. Linked to the Log Analytics Workspace in "workspace-based" mode (required
for all new App Insights resources — the older "classic" mode was retired in Feb 2024).
Once microservices send their connection string, you get distributed traces, dependency
graphs, exception tracking, and live metrics with no additional infrastructure.

---

### Step 2.1 — Check ACR name availability

ACR names must be globally unique across all of Azure. Verify your name before applying:

```powershell
az acr check-name --name acrantkartdev
```

Expected output if available:
```json
{
  "message": null,
  "nameAvailable": true,
  "reason": null
}
```

If `nameAvailable` is `false`, edit the name in `environments/dev/acr/terragrunt.hcl`:
```hcl
name = "acrantkartdev2026"   # or any unique alphanumeric name
```

Key Vault names are also globally unique. `kv-antkart-dev` is 14 characters and
distinctive — it is very likely available, but if not:
```hcl
name = "kv-antkart-dev2"   # append a suffix
```

---

### Step 2.2 — Deploy Log Analytics (first — App Insights depends on it)

```powershell
cd infrastructure/environments/dev/log-analytics
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_log_analytics_workspace.this   will be created

Plan: 1 to add, 0 to change, 0 to destroy.
```

```powershell
terragrunt apply
```

Expected output:
```
azurerm_log_analytics_workspace.this: Creating...
azurerm_log_analytics_workspace.this: Creation complete after 15s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
id           = "/subscriptions/.../workspaces/log-antkart-dev"
name         = "log-antkart-dev"
workspace_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

> **Notice:** `primary_shared_key` is marked `sensitive` — Terraform deliberately omits
> it from the output. It's stored in state (encrypted in Blob Storage) and can be read
> with `terragrunt output -raw primary_shared_key` when needed.

---

### Step 2.3 — Deploy Application Insights

```powershell
cd ../app-insights
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_application_insights.this   will be created

Plan: 1 to add, 0 to change, 0 to destroy.
```

> **Notice:** Terragrunt resolved the workspace ID by reading the log-analytics module's
> state output — you didn't type the workspace ID anywhere. The `dependency` block in
> `app-insights/terragrunt.hcl` did this automatically.

```powershell
terragrunt apply
```

Expected output:
```
azurerm_application_insights.this: Creating...
azurerm_application_insights.this: Creation complete after 10s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
name = "appi-antkart-dev"
```

> `instrumentation_key` and `connection_string` are both marked sensitive — they won't
> appear in the output. Read them individually when needed:
> ```powershell
> terragrunt output -raw connection_string
> ```

---

### Step 2.4 — Deploy ACR

```powershell
cd ../acr
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_container_registry.this   will be created

Plan: 1 to add, 0 to change, 0 to destroy.
```

```powershell
terragrunt apply
```

Expected output:
```
azurerm_container_registry.this: Creating...
azurerm_container_registry.this: Creation complete after 30s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
id           = "/subscriptions/.../registries/acrantkartdev"
login_server = "acrantkartdev.azurecr.io"
name         = "acrantkartdev"
```

---

### Step 2.5 — Deploy Key Vault

```powershell
cd ../key-vault
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_key_vault.this                          will be created
+ azurerm_role_assignment.deployer_secrets_officer will be created

Plan: 2 to add, 0 to change, 0 to destroy.
```

> **Two resources:** the vault itself, and the role assignment granting your Terraform
> Service Principal the `Key Vault Secrets Officer` role. Without this role assignment,
> even the SP that created the vault cannot read or write secrets.

```powershell
terragrunt apply
```

Expected output:
```
azurerm_key_vault.this: Creating...
azurerm_key_vault.this: Creation complete after 45s
azurerm_role_assignment.deployer_secrets_officer: Creating...
azurerm_role_assignment.deployer_secrets_officer: Creation complete after 20s

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
id        = "/subscriptions/.../vaults/kv-antkart-dev"
name      = "kv-antkart-dev"
vault_uri = "https://kv-antkart-dev.vault.azure.net/"
```

---

### Step 2.6 — Verify in the Azure Portal

1. Go to https://portal.azure.com → **Resource groups** → **rg-antkart-dev-eastus**
2. You should now see these resources alongside the VNet and NSGs from Week 1:
   | Resource | Type |
   |----------|------|
   | `acrantkartdev` | Container registry |
   | `kv-antkart-dev` | Key vault |
   | `log-antkart-dev` | Log Analytics workspace |
   | `appi-antkart-dev` | Application Insights |

3. Click **`kv-antkart-dev`** → **Access control (IAM)** → **Role assignments**
   You should see your Service Principal listed with the role **Key Vault Secrets Officer**.
   This confirms RBAC authorization is working — no "Access policies" blade needed.

4. Click **`appi-antkart-dev`** → look at the **Overview** pane.
   You should see `Workspace: log-antkart-dev` — confirming workspace-based mode.

5. Click **`acrantkartdev`** → **Properties**. Note:
   - Admin user: **Disabled** ✓
   - Login server: `acrantkartdev.azurecr.io`

---

### Cost note for Section 2

| Resource | Monthly cost (dev) |
|----------|-------------------|
| ACR Basic | ~$5 |
| Key Vault standard | ~$0 (< 10k operations/month in dev) |
| Log Analytics (first 5 GB free) | $0 |
| Application Insights (workspace-based, data in LA) | $0 |
| **Section 2 total** | **~$5/month** |

Running total after Week 1 + Week 2: **~$5/month** (networking is free; resource group is free).

ACR upgrade path: when the AKS cluster is hardened to private networking, changing
`sku = "Premium"` in `acr/terragrunt.hcl` + one `terragrunt apply` upgrades the
registry in place. No recreation, no image loss.

---

### Try this — Store and retrieve a secret in Key Vault

This experiment confirms that RBAC is working and gives you the `az keyvault` CLI
workflow you'll use every time you need to manage secrets.

```powershell
# Make sure your ARM_ environment variables are set (from Step 1.1)
# and that you're authenticated as the Terraform SP

# Store a test secret
az keyvault secret set `
  --vault-name kv-antkart-dev `
  --name "TestSecret" `
  --value "hello-from-antkart"
```

Expected output:
```json
{
  "id": "https://kv-antkart-dev.vault.azure.net/secrets/TestSecret/...",
  "name": "TestSecret",
  "value": "hello-from-antkart"
}
```

```powershell
# Retrieve it
az keyvault secret show `
  --vault-name kv-antkart-dev `
  --name "TestSecret" `
  --query value `
  -o tsv
```

Expected output:
```
hello-from-antkart
```

```powershell
# List all secrets in the vault
az keyvault secret list --vault-name kv-antkart-dev -o table
```

```powershell
# Clean up the test secret
az keyvault secret delete --vault-name kv-antkart-dev --name "TestSecret"
# (It goes into soft-deleted state — won't affect anything)
```

> **What this teaches:**
> The `az keyvault secret set` command worked because the Terraform SP now has the
> `Key Vault Secrets Officer` role — granted by the role assignment created in Step 2.5.
> If you try the same command with a user or SP that has no role assignment on this
> vault, it will fail with `403 Forbidden`. That's RBAC working exactly as intended.
>
> In Week 3, when AKS is deployed, you'll store the real secrets (Razorpay keys, DB
> passwords, App Insights connection string) and mount them into pods via the Secrets
> Store CSI Driver — no credentials in Docker images or Kubernetes manifests.

---

### Step 2.7 — Troubleshooting

| Problem | Symptoms | Fix |
|---------|----------|-----|
| **ACR name taken** | `RegistryNameAlreadyExists` during apply | Check availability: `az acr check-name --name acrantkartdev`. Change name in `acr/terragrunt.hcl` and re-apply |
| **Key Vault name in soft-delete** | `VaultAlreadyExists: A vault with the same name already exists in deleted state` | Purge it: `az keyvault purge --name kv-antkart-dev --location eastus`. Then re-apply |
| **Role assignment 403** | `AuthorizationFailed: does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'` | `Contributor` role does NOT include the right to create role assignments. Grant the SP `User Access Administrator` at the subscription scope (one-time, run as a subscription Owner): `az role assignment create --assignee "<SP-object-id>" --role "User Access Administrator" --scope "/subscriptions/<sub-id>"`. Then re-run `terragrunt apply` — the vault is already created, only the role assignment will be retried |
| **App Insights workspace_id missing** | `workspace_id is required` | Deploy log-analytics first. Check `terragrunt output` in the log-analytics directory — if it shows no outputs, the workspace wasn't applied |
| **Sensitive output blank** | `terragrunt output connection_string` returns empty | Add `-raw` flag: `terragrunt output -raw connection_string` |
| **KV secret set 403 — wrong identity** | `ForbiddenByRbac: Assignment: (not found)` — the caller object ID in the error is different from the Terraform SP's object ID | You are running `az keyvault` as your personal `az login` account, not the Terraform SP. The SP got the role; your personal account has none. Grant your personal account the role: `az role assignment create --assignee-object-id "<your-oid-from-error>" --assignee-principal-type User --role "Key Vault Secrets Officer" --scope "/subscriptions/1a69c45b-82ed-4ec6-972e-c9a5933e6fd0/resourceGroups/rg-antkart-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-antkart-dev"`. Wait 1-2 minutes then retry |
| **KV secret set 403 — propagation** | `Caller is not authorized` but the role assignment exists (you just applied) | RBAC changes take 1-5 minutes to propagate across Azure. Wait and retry |

---

## Section 3: Data and Messaging Infrastructure — Cosmos DB & Service Bus

### What you're about to do

In this section you'll provision two services that replace the Docker containers AntKart used in Phase 1:

- **Azure Cosmos DB (MongoDB API, Serverless)** — replaces the local `mongo:7` Docker container for AK.Products; wire-compatible with `MongoDB.Driver`
- **Azure Service Bus (Standard SKU)** — replaces the local `rabbitmq:3-management` Docker container; wire-compatible with MassTransit

Both services write their connection strings to the Key Vault you deployed in Section 2. No credentials touch your code or terminal output.

### Why it matters

**Why Cosmos DB instead of keeping a self-hosted MongoDB container?**

The Phase 1 `mongo:7` Docker container is fine for a single developer's laptop. In Azure:
- There's no managed MongoDB service from Microsoft — you'd run a VM with MongoDB, own the patching, backups, and availability
- Cosmos DB with the MongoDB API is wire-compatible with `MongoDB.Driver` — your application code doesn't change; only the connection string changes
- Serverless billing means zero idle cost: you pay per Request Unit consumed, not per hour the container exists

**Why Service Bus instead of keeping RabbitMQ?**

Same managed-service argument: no broker cluster to operate, native Azure Monitor integration, and MassTransit's Service Bus transport is configured with one line change — the consumer classes and integration events are unchanged. See ADR-011 for the full SKU comparison.

**Why does the Service Bus cost warning matter?**

Cosmos DB Serverless has zero idle cost — it's safe to leave running all the time. Service Bus Standard charges ~$10/month even when no messages flow. Unlike Cosmos DB (which holds your product data), Service Bus is stateless messaging infrastructure — destroy it between dev sessions when you're not actively developing the messaging features.

---

### Step 3.1 — Deploy Cosmos DB

Set your ARM environment variables if not already set (same as Step 1.1 in Section 1):

```powershell
$env:ARM_CLIENT_ID     = "<sp-client-id>"
$env:ARM_CLIENT_SECRET = "<sp-client-secret>"
$env:ARM_TENANT_ID     = "4cacc56a-0d38-46c4-ba20-429d51d7b449"
$env:ARM_SUBSCRIPTION_ID = "1a69c45b-82ed-4ec6-972e-c9a5933e6fd0"
```

```powershell
cd infrastructure/environments/dev/cosmosdb
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_cosmosdb_account.this         will be created
+ azurerm_cosmosdb_mongo_database.products  will be created
+ azurerm_key_vault_secret.cosmos_connection_string  will be created

Plan: 3 to add, 0 to change, 0 to destroy.
```

> **Three resources:** the account (the top-level container), the MongoDB database inside it
> (`antkart-products`), and a Key Vault secret holding the connection string. Cosmos DB
> account creation typically takes 2-4 minutes.

```powershell
terragrunt apply
```

Expected output:
```
azurerm_cosmosdb_account.this: Creating...
azurerm_cosmosdb_account.this: Still creating... [1m elapsed]
azurerm_cosmosdb_account.this: Still creating... [2m elapsed]
azurerm_cosmosdb_account.this: Creation complete after 3m

azurerm_cosmosdb_mongo_database.products: Creating...
azurerm_cosmosdb_mongo_database.products: Creation complete after 10s

azurerm_key_vault_secret.cosmos_connection_string: Creating...
azurerm_key_vault_secret.cosmos_connection_string: Creation complete after 5s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:
database_name = "antkart-products"
endpoint      = "https://cosmos-antkart-dev.documents.azure.com:443/"
id            = "/subscriptions/.../databaseAccounts/cosmos-antkart-dev"
name          = "cosmos-antkart-dev"
```

> `connection_string` is marked sensitive — it won't appear in the output. The string
> has already been written to Key Vault. Read it when needed:
> ```powershell
> terragrunt output -raw connection_string
> # Or read directly from Key Vault:
> az keyvault secret show --vault-name kv-antkart-dev --name "cosmos-connection-string" --query value -o tsv
> ```

> **Name uniqueness:** If you see `DatabaseAccountAlreadyExists`, the name
> `cosmos-antkart-dev` is taken globally. Change the `name` input in
> `environments/dev/cosmosdb/terragrunt.hcl` (e.g., `cosmos-antkart-dev-2026`) and re-apply.

---

### Step 3.2 — Deploy Service Bus

```powershell
cd ../servicebus
terragrunt init
terragrunt plan
```

Expected plan:
```
+ azurerm_servicebus_namespace.this                          will be created
+ azurerm_servicebus_queue.order_commands                    will be created
+ azurerm_servicebus_topic.integration_events                will be created
+ azurerm_servicebus_subscription.products                   will be created
+ azurerm_servicebus_subscription.notification               will be created
+ azurerm_key_vault_secret.servicebus_connection_string      will be created

Plan: 6 to add, 0 to change, 0 to destroy.
```

> **Six resources in one apply:** the namespace (the top-level container), a command queue,
> an event topic, two independent subscriptions on that topic (one for AK.Products, one for
> AK.Notification), and the Key Vault secret for the connection string.

```powershell
terragrunt apply
```

Expected output:
```
azurerm_servicebus_namespace.this: Creating...
azurerm_servicebus_namespace.this: Creation complete after 45s

azurerm_servicebus_queue.order_commands: Creating...
azurerm_servicebus_queue.order_commands: Creation complete after 15s

azurerm_servicebus_topic.integration_events: Creating...
azurerm_servicebus_topic.integration_events: Creation complete after 10s

azurerm_servicebus_subscription.products: Creating...
azurerm_servicebus_subscription.notification: Creating...
azurerm_servicebus_subscription.products: Creation complete after 10s
azurerm_servicebus_subscription.notification: Creation complete after 10s

azurerm_key_vault_secret.servicebus_connection_string: Creating...
azurerm_key_vault_secret.servicebus_connection_string: Creation complete after 5s

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:
namespace_id   = "/subscriptions/.../namespaces/sb-antkart-dev"
namespace_name = "sb-antkart-dev"
```

> The `connection_string` output is marked sensitive. Retrieve it from Key Vault:
> ```powershell
> az keyvault secret show --vault-name kv-antkart-dev --name "servicebus-connection-string" --query value -o tsv
> ```

---

### Step 3.3 — Verify in the Azure Portal

1. Go to **portal.azure.com** → **Resource groups** → **rg-antkart-dev-eastus**
2. You should now see these additional resources alongside the ones from Sections 1 and 2:

   | Resource | Type |
   |----------|------|
   | `cosmos-antkart-dev` | Azure Cosmos DB account |
   | `sb-antkart-dev` | Service Bus Namespace |

3. **Cosmos DB:** Click `cosmos-antkart-dev` → **Data Explorer** → expand **antkart-products** database. You'll see the database is empty — collections will be created by AK.Products on first startup (Cosmos DB MongoDB API creates collections lazily).

4. **Cosmos DB — Serverless confirmation:** Click **Settings** → **Features**. The **Serverless** capability should be listed as enabled. There is no throughput provisioned (no RU/s slider) — billing is purely per-operation.

5. **Service Bus messaging topology:** Click `sb-antkart-dev` → **Queues** — you should see `order-commands`. Click **Topics** — you should see `integration-events`. Click `integration-events` → **Subscriptions** — you should see `products-subscription` and `notification-subscription`, each with their own independent message cursor.

6. **Key Vault secrets:** Click `kv-antkart-dev` → **Secrets**. You should now see:
   - `cosmos-connection-string`
   - `servicebus-connection-string`

   Click each secret → **CURRENT VERSION** → **Show Secret Value** to confirm the values were written correctly.

---

### Step 3.4 — Cost note for Section 3

| Resource | Billing model | Estimated cost |
|----------|--------------|----------------|
| Cosmos DB (Serverless) | Per RU consumed | ~$0 idle; ~$1-3/month light dev use |
| Service Bus Standard | ~$10/month base + per-op | ~$10/month when running |
| **Section 3 addition** | | **~$1–13/month** |
| **Running total (Sections 1-3)** | | **~$6–18/month** |

**Save the Service Bus cost when not developing messaging features:**
```powershell
cd infrastructure/environments/dev/servicebus
terragrunt destroy   # saves ~$10/month; takes ~30 seconds

# When you need it again:
terragrunt apply     # recreates in ~60 seconds
```

Terragrunt updates the Key Vault secret with the new connection string automatically on re-apply. Restart any running services to pick up the refreshed secret.

---

### Try this — Send and peek a test message via the Service Bus Explorer

The Azure portal's built-in Service Bus Explorer lets you send and receive messages without writing any code. This is the fastest way to verify the namespace is working.

**Send a test message to the queue:**

1. Portal → `sb-antkart-dev` → **Queues** → `order-commands`
2. Click **Service Bus Explorer** (in the left menu)
3. Select **Send messages** tab
4. Set **Content type** to `application/json`
5. Paste this body:
   ```json
   {
     "orderId": "test-001",
     "userId": "user-test",
     "total": 99.99
   }
   ```
6. Click **Send** — you should see `Message sent successfully`

**Peek at the message (non-destructive read):**

1. Switch to the **Peek from start** tab
2. Click **Peek** — the message body appears below
3. The message count on the queue stays at 1 (peek doesn't consume the message)

**Dead-letter a message by exhausting delivery attempts:**

1. Go to **Receive messages** tab → set **Receive mode** to `ReceiveAndDelete`
2. Receive 10 times (or leave the count at 10) — Azure automatically dead-letters the message after `max_delivery_count = 10` redelivery failures
3. Switch to the **Dead-letter** sub-queue: URL bar will show `/$DeadLetterQueue`
4. Peek from start — the dead-lettered message appears with properties showing the dead-letter reason

> **Why this matters:** In production, if AK.Order crashes while processing a message 10 times, the message doesn't disappear — it lands in the dead-letter queue where you can inspect it and replay it after fixing the bug. This is the audit trail pattern that makes the system observable.

---

### Try this — Verify the Cosmos DB connection string works

This confirms that the MongoDB-API connection string written to Key Vault is valid and can authenticate with the account.

```powershell
# Read the connection string from Key Vault
$connStr = az keyvault secret show `
  --vault-name kv-antkart-dev `
  --name "cosmos-connection-string" `
  --query value -o tsv

# Verify it starts with "mongodb://" (MongoDB API format)
Write-Host $connStr.Substring(0, 50)
# Expected: mongodb://cosmos-antkart-dev:...
```

> The connection string format is `mongodb://<account>:<key>@<account>.mongo.cosmos.azure.com:10255/?ssl=true&...`
> This is exactly what `MongoDB.Driver`'s `MongoClient` accepts.
> In AK.Products' `appsettings.json`, replace the `MongoDbSettings:ConnectionString` value
> with this string (or better: store it in Key Vault and read it via the Secrets Store CSI Driver in AKS).

---

### Step 3.5 — Troubleshooting

| Problem | Symptoms | Fix |
|---------|----------|-----|
| **Cosmos DB name taken** | `DatabaseAccountAlreadyExists` during apply | Cosmos DB account names are globally unique. Change `name` in `cosmosdb/terragrunt.hcl` (e.g., `cosmos-antkart-dev-2026`) and re-apply |
| **Cosmos DB name taken (soft-delete)** | `DatabaseAccountAlreadyExists` after a destroy | Cosmos DB accounts have a 30-day soft-delete period. Purge it: `az cosmosdb delete --name cosmos-antkart-dev --resource-group rg-antkart-dev-eastus --yes` — or just use a different name suffix |
| **Service Bus name taken** | `NamespaceAlreadyExists` during apply | Change `name` in `servicebus/terragrunt.hcl` (e.g., `sb-antkart-dev-2026`) and re-apply |
| **KV secret 403 on cosmos secret** | `ForbiddenByRbac` when Terraform writes the connection string secret | The Terraform SP needs `Key Vault Secrets Officer` on the vault. Check the role assignment exists: `az role assignment list --scope /subscriptions/.../vaults/kv-antkart-dev --role "Key Vault Secrets Officer"` |
| **Cosmos DB apply takes >10 minutes** | Terraform shows "Still creating..." for a long time | Normal — Cosmos DB global replication setup takes 3-8 minutes. Wait; do not cancel |
| **MongoDB connection refused from app** | App can't connect after switching from local Docker Mongo | Confirm connection string from Key Vault starts with `mongodb://`. Ensure `ssl=true` is in the query string. Cosmos DB MongoDB API requires TLS |
| **Service Bus send 401** | `UnauthorizedException` when sending a message from the app | Connection string changed after a destroy/recreate cycle. Restart the service to reload the Key Vault secret |

---

## Section 4: Migrating Messaging to Azure Service Bus (Enterprise Dev Model)

### The enterprise development model — developing against real cloud services

Before touching any code, it's important to understand the shift in how we develop.

**Phase 1 (local stack):** Every dependency ran as a Docker container on your laptop. `docker-compose up` started MongoDB, PostgreSQL, Redis, RabbitMQ, Keycloak, and all six microservices together. You worked in a fully local bubble.

**Phase 2 (enterprise model):** We run only the service(s) we are actively developing locally. Everything else — messaging (Service Bus), the product database (Cosmos DB), secrets (Key Vault) — runs in Azure. You develop locally, but against real cloud infrastructure.

**Why is this the right approach?**

| Concern | Full local stack | Enterprise model |
|---------|-----------------|-----------------|
| **Environment parity** | Local broker behaves differently to Service Bus — different dead-lettering, different TTL semantics, different retry behaviour | You test against the actual service you'll run in production — no surprises at deploy time |
| **Dependency sprawl** | 12+ containers running at once, eating RAM and startup time | Run only what you need for the feature you're building |
| **Security realism** | Local RabbitMQ has no auth — your code never exercises credential flows | Token auth via `az login` works the same way Workload Identity will work in AKS — you test the auth path locally |
| **Realistic failure modes** | Local broker never flaps, never rate-limits, never has latency | Real cloud services have real transient errors — your retry policies are tested for real |
| **Cost** | No Azure cost for messaging locally | Service Bus Standard is ~$10/month — manageable for a dev namespace that you can destroy when idle |

This is how enterprise teams build distributed systems: local code, cloud dependencies. It's a mindset shift from "everything must be local" to "cloud is where the system lives — let's develop against it."

---

### Azure Service Bus — a complete explanation

**What is Azure Service Bus?**

Azure Service Bus is a fully managed enterprise message broker hosted in Azure. Think of it as a post office for your microservices: services drop off messages and pick up messages without ever needing to know about each other directly.

It replaces the RabbitMQ Docker container used in Phase 1. The replacement is managed (no server to operate), SLA-backed (99.9% uptime), and natively integrated with Azure authentication.

**Namespaces**

The top-level container is a **namespace** — a unique hostname in Azure: `sb-antkart-dev.servicebus.windows.net`. Every queue, topic, and subscription lives inside the namespace. The namespace is what you authenticate against.

**Queues**

A queue implements **point-to-point** messaging: one publisher, one consumer. Each message is delivered to exactly one consumer, and once processed, it's gone.

```
Publisher ──► [queue] ──► Consumer A (only one consumer gets each message)
```

Use queues for **commands**: "process this payment", "send this email". Commands should be handled by exactly one service instance. AntKart uses a conceptual `order-commands` queue pattern — the SAGA in AK.Order is the single handler.

**Topics and subscriptions**

A topic implements **publish-subscribe** messaging: one publisher, many independent subscribers. Each subscription on a topic gets an independent copy of every message.

```
Publisher ──► [topic]
                 ├──► [subscription A] ──► Consumer A (gets its own copy)
                 └──► [subscription B] ──► Consumer B (gets its own copy)
```

Use topics for **events**: "an order was created". Multiple services react to the same event independently. In AntKart:

```
AK.Order publishes OrderCreatedIntegrationEvent
   ──► integration-events topic
         ├──► order-order-saga subscription       ──► OrderSaga in AK.Order
         ├──► products-reserve-stock subscription ──► ReserveStockConsumer in AK.Products
         ├──► notification-order-created          ──► OrderCreatedConsumer in AK.Notification
         └──► cart-clear-cart-on-order-confirmed  ──► ClearCartOnOrderConfirmedConsumer in AK.ShoppingCart
```

Adding a new consumer to an event requires only a new subscription — the publisher never changes.

**Dead-letter queue**

Every queue and subscription automatically has a dead-letter sub-queue. Messages land there when:
- A consumer fails to process the message after `max_delivery_count` attempts (default: 10)
- The message TTL expires before being processed

Dead-lettered messages are visible in the Azure portal's Service Bus Explorer. You can:
- Read the message body and delivery metadata to diagnose what went wrong
- Replay the message to the main queue/subscription after fixing the bug

This is the "observable failure" pattern — broken messages are preserved and inspectable rather than silently discarded.

**How Service Bus compares to RabbitMQ**

| Feature | RabbitMQ (Phase 1) | Azure Service Bus (Phase 2) |
|---------|-------------------|----------------------------|
| Hosting | Docker container, self-managed | Fully managed Azure service |
| Auth | Username + password | Token-based (Azure AD) |
| SLA | None (single container) | 99.9% (Standard) |
| Dead-lettering | Manual setup | Built-in |
| Azure Monitor | Manual exporter | Native metrics and alerts |
| MassTransit support | ✅ | ✅ (same consumer code) |
| Dev cost | $0 (local) | ~$10/month (destroy when idle) |

The critical point: **MassTransit abstracts the broker**. Consumer classes, the SAGA state machine, the EF Core outbox — none of them know whether the transport is RabbitMQ or Service Bus. The Week 4 migration changed exactly one file's transport configuration and nothing else in the business logic.

---

### Token-based authentication with DefaultAzureCredential

**The problem with connection strings**

The traditional way to connect to a message broker is a connection string:
```
Endpoint=sb://sb-antkart-dev.servicebus.windows.net;SharedAccessKey=...
```

A connection string is a secret. It must be stored somewhere, rotated periodically, and kept out of source control. If it leaks, anyone with the string can send and receive messages until you rotate it. It also creates an ops problem: different secrets for local dev, staging, and production.

**The token-based solution**

Azure AD issues short-lived tokens (1 hour TTL) to authenticated identities. A token proves identity without exposing a long-lived secret. The token is obtained automatically by the SDK — you never handle it in your application code.

`DefaultAzureCredential` is the credential object from the `Azure.Identity` package. It implements a **credential chain** — it tries each authentication source in order and stops at the first one that succeeds:

```
DefaultAzureCredential tries, in order:
  1. EnvironmentCredential       — reads ARM_CLIENT_ID + ARM_CLIENT_SECRET environment variables
  2. WorkloadIdentityCredential  — reads Kubernetes federated token (AKS, Week 7+)
  3. ManagedIdentityCredential   — reads Azure VM/App Service managed identity
  4. SharedTokenCacheCredential  — reads Visual Studio token cache
  5. VisualStudioCredential      — reads Visual Studio sign-in
  6. AzureCliCredential          — reads `az login` session token ← WINS on your machine
  7. AzurePowerShellCredential   — reads Az PowerShell login
  8. InteractiveBrowserCredential — opens a browser sign-in window (last resort)
```

**On your developer machine:**

You have run `az login`. The Azure CLI stores your session token in `~/.azure/accessTokens.json`. When your service starts and first tries to connect to Service Bus, `DefaultAzureCredential` reaches step 6, reads your CLI token, and exchanges it for a Service Bus access token. No connection string. No secret file. Just your existing login session.

**In AKS (Week 7+):**

The pod has a projected service account token mounted at a path managed by the Workload Identity webhook. `DefaultAzureCredential` reaches step 2 (`WorkloadIdentityCredential`), reads the projected token, and exchanges it for a Service Bus access token. No secret mounted in the pod. No connection string in a Kubernetes Secret object.

**Same code. Both places.** The credential source is an environment concern — the code is identical.

**What this looks like in the code:**

```csharp
// AK.BuildingBlocks/Messaging/MassTransitExtensions.cs
cfg.Host(new Uri($"sb://{fullyQualifiedNamespace}/"), h =>
{
    h.TokenCredential = new DefaultAzureCredential();
});
```

`fullyQualifiedNamespace` is read from `appsettings.json`:
```json
"ServiceBus": {
  "FullyQualifiedNamespace": "sb-antkart-dev.servicebus.windows.net"
}
```

The namespace FQDN is not a secret — it's the public DNS name of the namespace. Only the token (obtained lazily by the SDK at runtime) proves identity.

---

### MassTransit as the messaging abstraction

MassTransit is the layer that sits between your application code and the message broker. Your consumers, sagas, and publishers talk to MassTransit's APIs. MassTransit translates those calls to whatever transport is configured — RabbitMQ, Service Bus, Amazon SQS, or even in-memory for tests.

This is why the Week 4 migration touched zero consumer code: consumers call `context.Publish()`, `context.Send()`, and `context.RespondAsync()` — MassTransit APIs. The transport is an implementation detail.

**How MassTransit maps to Service Bus topology:**

MassTransit automatically creates Service Bus entities when a service starts (requires Manage permission from the Data Owner role):

- **One topic per message type**, named from the .NET type's full name:
  ```
  ak.buildingblocks.messaging.integrationevents:ordercreatedintegrationevent
  ```
- **One subscription per consumer endpoint**, named `<servicePrefix>-<consumer-kebab>`:
  ```
  products-reserve-stock   ← ReserveStockConsumer in AK.Products, prefix "products"
  notification-order-created ← OrderCreatedConsumer in AK.Notification, prefix "notification"
  ```

The service prefix (`"products"`, `"notification"`, etc.) passed to `AddServiceBusMassTransit()` ensures uniquely named subscriptions. Without it, two services consuming the same event would compete for messages on a single subscription — only one would receive each message. With unique prefixes, each service gets its own subscription and each receives every message independently (fan-out).

---

### Step 4.1 — Grant yourself the Azure Service Bus Data Owner role

Before running any service locally, your Azure identity needs permission to create topics, send messages, and receive messages on the Service Bus namespace.

```powershell
# Step 1: Get your signed-in object ID
$myObjectId = az ad signed-in-user show --query id -o tsv
Write-Host "Your object ID: $myObjectId"

# Step 2: Get the Service Bus namespace resource ID
$namespaceId = az servicebus namespace show `
  --name sb-antkart-dev `
  --resource-group rg-antkart-dev-eastus `
  --query id -o tsv
Write-Host "Namespace resource ID: $namespaceId"

# Step 3: Grant the role (paste the values from above if the variables didn't capture)
az role assignment create `
  --role "Azure Service Bus Data Owner" `
  --assignee $myObjectId `
  --scope $namespaceId
```

Expected output from step 3:
```json
{
  "principalId": "<your-object-id>",
  "roleDefinitionName": "Azure Service Bus Data Owner",
  "scope": "/subscriptions/.../namespaces/sb-antkart-dev"
}
```

**What "Azure Service Bus Data Owner" grants:**
- **Manage** — create and delete topics, queues, subscriptions (needed for MassTransit auto-topology)
- **Send** — publish messages to topics and queues
- **Listen/Receive** — consume messages from subscriptions and queues

> **RBAC propagation:** Role assignments in Azure take 1-5 minutes to propagate. If you see `401 Unauthorized` from Service Bus in the first few minutes after assigning, wait and retry. This is expected.

---

### Step 4.2 — Confirm az login and DefaultAzureCredential

Before starting any service, confirm your CLI session is active and pointing at the right tenant:

```powershell
# Confirm you are logged in and which account is active
az account show --query "{name:name, user:user.name, tenantId:tenantId}" -o table
```

Expected output:
```
Name              User                        TenantId
----------------  --------------------------  ------------------------------------
AntKart           antkartadmin@gmail.com      4cacc56a-0d38-46c4-ba20-429d51d7b449
```

If you see a different subscription or tenant:
```powershell
az login --tenant 4cacc56a-0d38-46c4-ba20-429d51d7b449
az account set --subscription 1a69c45b-82ed-4ec6-972e-c9a5933e6fd0
```

**How to verify DefaultAzureCredential will find your CLI session:**

```powershell
# Install Azure.Identity test script (or just trust the chain — it always finds az login)
az account get-access-token --resource "https://servicebus.azure.net/" --query accessToken -o tsv | Select-Object -First 1 -ExpandProperty Length
# If this returns a non-zero number, the token was retrieved successfully
```

---

### Step 4.3 — Run services locally against Azure Service Bus

In the enterprise model, you run only the services you are working on. For the complete order flow, you need four services running locally:

| Service | Port | What it does in the flow |
|---------|------|--------------------------|
| AK.Order | 5080 | Accepts order creation; runs OrderSaga; publishes OrderCreatedIntegrationEvent |
| AK.Products | 5077 | Consumes OrderCreated; reserves stock; publishes StockReserved or StockReservationFailed |
| AK.Payments | 5086 | Consumes OrderConfirmed (stub); uses Razorpay for payment processing |
| AK.Notification | 5087 | Consumes all events; sends emails (via Mailhog locally) |

You also need local infrastructure (no cloud for these):
```powershell
# Start local infrastructure (postgres, redis, mailhog — not rabbitmq, that's gone)
docker-compose up postgres redis mailhog -d
```

Open four terminal windows and run each service:

```powershell
# Terminal 1 — Order service
cd AK.Order/AK.Order.API
dotnet run

# Terminal 2 — Products service
cd AK.Products/AK.Products.API
dotnet run

# Terminal 3 — Payments service
cd AK.Payments/AK.Payments.API
dotnet run

# Terminal 4 — Notification service
cd AK.Notification/AK.Notification.API
dotnet run
```

**What to look for in startup logs:**

Each service should log something like:
```
info: MassTransit[0]
      Bus started: azure-service-bus://sb-antkart-dev.servicebus.windows.net/
```

If you see this, MassTransit connected to Service Bus using your `az login` credential and auto-created its subscriptions. If you see a `401 Unauthorized` or `TokenRequestFailedException`, see the troubleshooting table below.

**VS Code compound launch (optional):**

Add this to `.vscode/launch.json` to start all four services with F5:
```json
{
  "version": "0.2.0",
  "compounds": [
    {
      "name": "AntKart Order Flow",
      "configurations": ["AK.Order", "AK.Products", "AK.Payments", "AK.Notification"]
    }
  ],
  "configurations": [
    { "name": "AK.Order",        "type": "coreclr", "request": "launch", "preLaunchTask": "build", "program": "${workspaceFolder}/AK.Order/AK.Order.API/bin/Debug/net9.0/AK.Order.API.dll", "cwd": "${workspaceFolder}/AK.Order/AK.Order.API" },
    { "name": "AK.Products",     "type": "coreclr", "request": "launch", "preLaunchTask": "build", "program": "${workspaceFolder}/AK.Products/AK.Products.API/bin/Debug/net9.0/AK.Products.API.dll", "cwd": "${workspaceFolder}/AK.Products/AK.Products.API" },
    { "name": "AK.Payments",     "type": "coreclr", "request": "launch", "preLaunchTask": "build", "program": "${workspaceFolder}/AK.Payments/AK.Payments.API/bin/Debug/net9.0/AK.Payments.API.dll", "cwd": "${workspaceFolder}/AK.Payments/AK.Payments.API" },
    { "name": "AK.Notification", "type": "coreclr", "request": "launch", "preLaunchTask": "build", "program": "${workspaceFolder}/AK.Notification/AK.Notification.API/bin/Debug/net9.0/AK.Notification.API.dll", "cwd": "${workspaceFolder}/AK.Notification/AK.Notification.API" }
  ]
}
```

---

### Step 4.4 — Place a test order and trace the flow

First, get a JWT token (if running without a gateway, call Order directly with auth disabled in dev, or use a Keycloak token):

```powershell
# If running Order with auth disabled for testing, call directly:
$orderPayload = @'
{
  "userId": "test-user-001",
  "customerEmail": "test@antkart.com",
  "customerName": "Test User",
  "shippingAddress": {
    "street": "123 Main St",
    "city": "Chennai",
    "state": "Tamil Nadu",
    "postalCode": "600001",
    "country": "India"
  },
  "items": [
    {
      "productId": "MEN-SHIR-001",
      "productName": "Classic Cotton Shirt",
      "quantity": 2,
      "unitPrice": 899.00
    }
  ]
}
'@

$response = Invoke-RestMethod -Uri "http://localhost:5080/api/orders" -Method POST -Body $orderPayload -ContentType "application/json"
Write-Host "Order created: $($response.orderNumber)"
```

**What happens after this call:**

1. **AK.Order** creates the order in PostgreSQL, publishes `OrderCreatedIntegrationEvent` via the outbox (written to `OutboxMessages` table first, then delivered to Service Bus by MassTransit's outbox worker)
2. **Service Bus** delivers the event to all subscriptions bound to the `ordercreatedintegrationevent` topic
3. **AK.Products** (`products-reserve-stock` subscription) receives the event, checks stock, publishes `StockReservedIntegrationEvent`
4. **AK.Notification** (`notification-order-created` subscription) receives the event, sends an order confirmation email
5. **AK.ShoppingCart** (`cart-clear-cart-on-order-confirmed` subscription) receives the event, clears the user's cart
6. **OrderSaga** (`order-order-saga` subscription) receives `OrderCreatedIntegrationEvent`, transitions to `StockPending`, waits
7. **OrderSaga** then receives `StockReservedIntegrationEvent`, publishes `OrderConfirmedIntegrationEvent`, finalizes
8. **AK.Order** consumers receive `OrderConfirmedIntegrationEvent`, update the order status to Confirmed
9. **AK.Notification** receives `OrderConfirmedIntegrationEvent`, sends a stock-confirmed email

---

### Step 4.5 — Verify message flow in the Azure Portal Service Bus Explorer

While the services are running and processing an order:

1. Go to **portal.azure.com** → **sb-antkart-dev** → **Topics**
2. Click any topic (e.g., `ak.buildingblocks.messaging.integrationevents:ordercreatedintegrationevent`)
3. Click **Service Bus Explorer** in the left menu
4. Switch to **Peek from start** → Click **Peek**
5. If a message is in-flight, you'll see it here. If processed, the count shows 0.

**To watch message counts in real time:**

1. Portal → **sb-antkart-dev** → **Metrics** (in the left menu)
2. Add metric: **Incoming Messages** — shows messages published per minute
3. Add metric: **Outgoing Messages** — shows messages consumed per minute
4. Add metric: **Dead-lettered Messages** — if this increases, a consumer is failing

**To inspect a dead-lettered message:**

1. Portal → **sb-antkart-dev** → **Topics** → select topic → **Subscriptions** → select subscription
2. Click **Service Bus Explorer** → switch to **Dead-letter** sub-queue
3. Click **Peek from start** — the failed message appears with metadata:
   - `DeadLetterReason` — why it was dead-lettered (e.g., `MaxDeliveryCountExceeded`)
   - `DeadLetterErrorDescription` — the exception message from the consumer
   - Message body — the original event JSON

---

### Step 4.6 — Set breakpoints in the SAGA and consumers

**Breakpoint in the OrderSaga:**

1. Open `AK.Order/AK.Order.Application/Sagas/OrderSaga.cs`
2. Set a breakpoint inside the `When(OrderCreated)` block (the `.Then(ctx => { ... })` callback)
3. Place an order via the API
4. The breakpoint will hit when the SAGA receives `OrderCreatedIntegrationEvent` from Service Bus
5. Inspect `ctx.Saga` to see the state being populated, `ctx.Message` to see the incoming event

**Breakpoint in a consumer:**

1. Open `AK.Products/AK.Products.Application/Consumers/ReserveStockConsumer.cs`
2. Set a breakpoint on the first line of `Consume(ConsumeContext<OrderCreatedIntegrationEvent> context)`
3. The breakpoint hits when AK.Products receives the event from its `products-reserve-stock` subscription

**Tracing a message end-to-end:**

Each `IIntegrationEvent` has an `EventId` (Guid) and `OccurredOn` (DateTimeOffset). Log the `EventId` when published in AK.Order and look for it in AK.Products and AK.Notification logs. MassTransit also sets a `MessageId` header on every Service Bus message — visible in the portal's Service Bus Explorer message details.

---

### Step 4.7 — Test the happy path and compensation path

**Happy path (stock available, payment succeeds):**

1. Create an order for a product with stock (e.g., `MEN-SHIR-001`, quantity 1)
2. Expected sequence:
   - OrderSaga: Initial → StockPending (after OrderCreated)
   - ReserveStockConsumer: decrements stock, publishes StockReserved
   - OrderSaga: StockPending → Confirmed (after StockReserved), publishes OrderConfirmed, saga row deleted
   - Order status in DB: Pending → Confirmed
3. Check Mailhog (`http://localhost:8025`): two emails should arrive (order confirmation + stock confirmed)

**Compensation path (stock exhausted):**

1. First, deplete stock for a product by creating many orders (or directly update MongoDB)
2. Create an order for the depleted product
3. Expected sequence:
   - OrderSaga: Initial → StockPending (after OrderCreated)
   - ReserveStockConsumer: stock check fails, publishes StockReservationFailed
   - OrderSaga: StockPending → Cancelled (after StockReservationFailed), publishes OrderCancelled, saga row deleted
   - Order status in DB: Pending → Cancelled
4. Check Mailhog: cancellation email should arrive

---

### Cost note for Week 4

No new Azure resources were created this week — Service Bus was provisioned in Week 3. The weekly cost is unchanged at ~$15-18/month.

Reminder: Service Bus Standard charges ~$10/month even when idle. Destroy when not actively developing messaging features:
```powershell
cd infrastructure/environments/dev/servicebus
terragrunt destroy   # free while idle
terragrunt apply     # recreates in ~60 seconds when needed
```

After destroying and recreating, MassTransit will re-create its topics and subscriptions on the next service startup (requires the role assignment to still be present).

---

### Step 4.8 — Troubleshooting

| Problem | Symptoms | Fix |
|---------|----------|-----|
| **Role not assigned** | `AuthorizationFailedException: 401 Unauthorized` on Service Bus connection | Grant the role (Step 4.1). Wait 1-5 min for RBAC propagation |
| **Not logged in** | `CredentialUnavailableException: DefaultAzureCredential failed to retrieve a token` | Run `az login --tenant 4cacc56a-0d38-46c4-ba20-429d51d7b449` |
| **Wrong tenant** | Token obtained but 401 on namespace | Run `az account show` — if tenant ID doesn't match `4cacc56a-...`, run `az login --tenant <correct-id>` |
| **Topology 403** | `MessagingEntityNotFoundException` or 403 when MassTransit starts | You need Manage permission — only `Azure Service Bus Data Owner` covers this. `Azure Service Bus Data Sender` and `Receiver` do not |
| **Messages not arriving** | Publisher succeeds but consumer never fires | Check the portal — is the topic created? Is the subscription created? Check subscription active message count vs dead-letter count |
| **Dead-letter spike** | Dead-letter message count increasing | Consumer is throwing. Check service logs for exceptions. Inspect the dead-letter message in the portal for `DeadLetterErrorDescription` |
| **Outbox not delivering** | Order created in DB but event never published | MassTransit outbox has a delivery worker. Check AK.Order logs for outbox worker activity. The `OutboxMessages` table should be empty after delivery |
| **SAGA stuck in StockPending** | `products-reserve-stock` subscription has active messages | AK.Products is not running, or its consumer threw. Start AK.Products and check for exceptions |
| **Service Bus namespace destroyed** | `MessagingEntityNotFoundException` — namespace doesn't exist | Run `terragrunt apply` in `environments/dev/servicebus`. MassTransit recreates topology on next start |

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
