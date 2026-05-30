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
| **KV secret set 403** | `Caller is not authorized` on `az keyvault secret set` | The role assignment may still be propagating (can take 2-5 minutes after apply). Wait and retry |

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
