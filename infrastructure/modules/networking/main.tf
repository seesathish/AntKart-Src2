# =============================================================================
# NETWORKING MODULE — MAIN
# File: infrastructure/modules/networking/main.tf
#
# PURPOSE:
#   Creates the complete network foundation for one AntKart environment:
#     - 1 Virtual Network (VNet)         — the private address space
#     - 3 Subnets                        — AKS nodes, private endpoints, AppGW
#     - 2 Network Security Groups (NSGs) — AKS and private endpoint subnets
#     - 2 NSG-Subnet Associations        — attaches NSGs to their subnets
#
# NETWORK TOPOLOGY:
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │  VNet: vnet-antkart-dev  (10.0.0.0/16)                      │
#   │                                                             │
#   │  ┌──────────────────────┐  NSG: nsg-aks-antkart-dev         │
#   │  │  snet-aks-antkart-dev│  - Allow VNet inbound             │
#   │  │  10.0.0.0/22         │  - Allow Azure LB inbound         │
#   │  │  (AKS nodes + pods)  │  - Deny all other inbound         │
#   │  └──────────────────────┘                                   │
#   │                                                             │
#   │  ┌──────────────────────┐  NSG: nsg-pe-antkart-dev          │
#   │  │  snet-pe-antkart-dev │  - Allow VNet inbound             │
#   │  │  10.0.4.0/24         │                                   │
#   │  │  (Private Endpoints) │                                   │
#   │  └──────────────────────┘                                   │
#   │                                                             │
#   │  ┌──────────────────────┐  (no NSG yet — reserved)          │
#   │  │  snet-appgw-antkart  │                                   │
#   │  │  10.0.5.0/27         │                                   │
#   │  │  (Application GW)    │                                   │
#   │  └──────────────────────┘                                   │
#   └─────────────────────────────────────────────────────────────┘
#
# DESIGN DECISIONS documented in ADR-009.
# =============================================================================

# -----------------------------------------------------------------------------
# LOCALS — Derived naming
#
# WHY compute names here with locals rather than more variables?
#   All child resource names follow a predictable pattern derived from the
#   VNet name. Computing them in locals means:
#     1. Callers only provide one name (the VNet name)
#     2. All child names are guaranteed consistent
#     3. If the project/env name changes, it propagates everywhere automatically
#
# EXAMPLE:
#   var.name = "vnet-antkart-dev"
#   name_suffix = "antkart-dev"   (strips the "vnet-" prefix)
#
#   snet-aks-antkart-dev, snet-pe-antkart-dev, snet-appgw-antkart-dev
#   nsg-aks-antkart-dev,  nsg-pe-antkart-dev
# -----------------------------------------------------------------------------
locals {
  # Strip the "vnet-" prefix to get a reusable suffix for all child resources.
  # replace() is Terraform's built-in string substitution function.
  name_suffix = replace(var.name, "vnet-", "")
}

# =============================================================================
# VIRTUAL NETWORK
#
# A VNet is Azure's private network — similar to an AWS VPC or an on-premises
# VLAN. Resources inside the VNet can communicate with each other by default.
# Resources outside cannot reach in unless you explicitly open the path.
#
# address_space defines the total IP pool. All subnets must be subsets of it.
# We pass this as a variable so different environments get different ranges
# (dev=10.0/16, staging=10.1/16, prod=10.2/16) — no overlap, safe for future
# VNet peering or VPN connectivity.
# =============================================================================
resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

# =============================================================================
# SUBNET: AKS Nodes and Pods
#
# WHY does AKS need such a large subnet (/22 = 1,024 IPs)?
#
#   AKS uses one of two network plugins:
#     - kubenet:    1 IP per NODE. Pods get NAT'd. /22 would support ~1,000 nodes.
#     - Azure CNI:  1 IP per POD. Each pod gets a real VNet IP. A 3-node cluster
#                   with 30 pods/node = 90 IPs immediately consumed.
#
#   AntKart uses Azure CNI (recommended for production — no NAT, full network
#   visibility, direct pod addressing). With Azure CNI, running out of subnet
#   IPs means you cannot schedule new pods — a hard failure, not just slowness.
#   /22 gives 1,024 IPs, enough for dev to grow significantly without subnet
#   changes (which require destroying and recreating the subnet).
#
# WHY are subnets expensive to resize?
#   In Azure, you can expand a subnet's CIDR (add space) but you cannot shrink
#   it or change its range while resources are deployed. Always size generously
#   upfront — the IPs are free.
# =============================================================================
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${local.name_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.aks]

  # Note: AKS-specific settings (service endpoints, delegations) will be added
  # here when the AKS module is created in a later week. For now, the subnet
  # is created clean and AKS will update it in-place.
}

# =============================================================================
# SUBNET: Private Endpoints
#
# Private Endpoints give Azure PaaS services (CosmosDB, Key Vault, ACR,
# Service Bus) a private IP inside your VNet. Without private endpoints:
#   - Traffic to CosmosDB goes over the public internet
#   - The service is accessible to the world (mitigated only by auth)
#
# With private endpoints:
#   - Traffic stays entirely within the Azure backbone
#   - The public endpoint can be disabled (network isolation)
#   - DNS resolves the service name to a private IP inside your VNet
#
# WHY private_endpoint_network_policies = "Disabled"?
#
#   This is one of Azure's most confusing settings. The name sounds like you're
#   DISABLING security — but it means the opposite of what you'd expect:
#
#   - "Disabled" = NSG and UDR rules are NOT enforced ON the private endpoint
#                  NIC itself. This is REQUIRED for private endpoints to work.
#                  Private endpoints need direct IP routing that NSGs would block.
#
#   - "Enabled"  = NSG rules ARE enforced on the PE NIC. This was added later
#                  to allow more granular control, but requires careful NSG design.
#
#   Until Week N when we add fine-grained NSG rules for private endpoints,
#   "Disabled" is the correct and standard value.
#
# CIDR sizing: /24 = 256 IPs. Each private endpoint takes 1 IP.
# AntKart will have: CosmosDB, Key Vault, ACR, Service Bus, PostgreSQL = 5 PEs.
# 256 is more than enough, even accounting for IP reservation (Azure reserves 5).
# =============================================================================
resource "azurerm_subnet" "pe" {
  name                 = "snet-pe-${local.name_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.pe]

  # Required for private endpoints to function. See the long comment above.
  private_endpoint_network_policies = "Disabled"
}

# =============================================================================
# SUBNET: Application Gateway (Reserved)
#
# This subnet is reserved NOW even though we're not deploying an Application
# Gateway yet. WHY reserve it early?
#
#   1. Azure Application Gateway v2 requires a DEDICATED subnet — it cannot
#      share with other resources.
#   2. You cannot insert a subnet between two existing subnets in a VNet.
#      The address space is partitioned sequentially. If we later need AppGW
#      but all the address space is allocated, we'd have to redesign the VNet.
#   3. The /27 (32 IPs) is enough for dev. Prod will need /24 (AGW v2 scales
#      up to 125 instances in prod, each consuming an IP).
#
# When we deploy AppGW in a later week, we'll configure this subnet with the
# specific settings AppGW requires (no service endpoint conflicts, specific NSG
# rules for port 65200-65535 for AGW management traffic).
# =============================================================================
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw-${local.name_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.appgw]
}

# =============================================================================
# NETWORK SECURITY GROUP: AKS Subnet
#
# WHY do we need an NSG on the AKS subnet if AKS manages its own NSG?
#
#   AKS creates and manages a SEPARATE NSG on the node pool's network interface
#   cards (NICs). That NSG handles Kubernetes-internal traffic (node port rules,
#   load balancer rules, etc.).
#
#   THIS NSG is at the SUBNET level — it's a security boundary around the entire
#   AKS subnet, controlling what gets in FROM outside the subnet.
#
#   Two layers of NSG = defence in depth:
#     - Subnet NSG: coarse-grained — "what traffic is allowed into this subnet at all"
#     - NIC NSG (AKS-managed): fine-grained — "what traffic reaches which node port"
#
# WHY explicit rules when Azure has implicit defaults?
#
#   Every NSG has implicit rules at priority 65000-65500:
#     - 65000 AllowVnetInBound     (allow all VNet traffic)
#     - 65001 AllowAzureLoadBalancerInBound
#     - 65500 DenyAllInBound
#
#   So technically we could skip the first two rules. BUT:
#     1. Explicit rules are visible in the Azure portal and auditable
#     2. They document INTENT — a future engineer knows why VNet is allowed
#     3. If someone later adds a more-restrictive rule above 65000, our
#        explicit rules at 100/110 make the intent clear
#
# DEFAULT-DENY PATTERN:
#   Rule at priority 4000 with Deny is redundant with the implicit 65500 deny,
#   but it makes the security posture visible at a glance: "deny everything not
#   explicitly permitted." This is the principle of least privilege made explicit.
# =============================================================================
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # ---------------------------------------------------------------------------
  # RULE: Allow all inbound traffic from within the VNet
  #
  # WHY: AKS nodes must communicate with each other (kubelet ↔ API server,
  # node-to-node pod traffic, health probes between components). All of this
  # is VNet-to-VNet traffic. Blocking it would break Kubernetes entirely.
  #
  # "VirtualNetwork" is an Azure service tag — it automatically resolves to
  # the current VNet's address space AND the address spaces of any peered VNets.
  # Using service tags instead of hardcoded CIDRs means this rule stays correct
  # even if the VNet address space changes.
  # ---------------------------------------------------------------------------
  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow all intra-VNet traffic. Required for AKS node-to-node and pod-to-pod communication."
  }

  # ---------------------------------------------------------------------------
  # RULE: Allow Azure Load Balancer health probes
  #
  # WHY: Azure Load Balancer sends health probes to nodes to determine if they
  # can receive traffic. The probe source IP is 168.63.129.16, but Azure
  # recommends using the "AzureLoadBalancer" service tag (which resolves to
  # that IP) so you don't need to remember the magic IP.
  #
  # If this rule is missing: health probes fail → LB marks all nodes unhealthy
  # → your Kubernetes services become unreachable, even if the pods are healthy.
  # This is a common "my service is down but pods are running" debugging path.
  # ---------------------------------------------------------------------------
  security_rule {
    name                       = "allow-azure-load-balancer-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    description                = "Allow Azure Load Balancer health probes. Without this, LB won't route traffic to AKS nodes."
  }

  # ---------------------------------------------------------------------------
  # RULE: Explicit default-deny inbound
  #
  # WHY: Azure already has an implicit deny-all at priority 65500. This rule
  # at 4000 makes the "deny everything else" intent VISIBLE and AUDITABLE.
  # Security reviewers scanning the NSG in the portal immediately see the
  # security posture: allow VNet, allow LB, deny all.
  #
  # This is the "default-deny" security pattern made explicit — like a comment
  # at the end of a switch statement that says "// should never reach here".
  # ---------------------------------------------------------------------------
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Explicit deny-all baseline. Azure has an implicit deny at 65500, but making it explicit documents intent."
  }
}

# =============================================================================
# NETWORK SECURITY GROUP: Private Endpoint Subnet
#
# WHY a separate NSG for the PE subnet?
#   The PE subnet has different security requirements than AKS:
#     - It RECEIVES connections from AKS pods (AKS subnet → PE subnet)
#     - It should NOT accept connections from the internet or other networks
#     - Private endpoints themselves don't initiate outbound traffic
#
# The rule allows inbound from the VNet — meaning AKS pods can connect to
# CosmosDB/Key Vault/ACR/Service Bus via their private IPs. Everything else
# is denied by the implicit 65500 rule.
#
# NOTE on private_endpoint_network_policies = "Disabled" on the subnet:
#   This NSG will be ASSOCIATED with the subnet, but with policies disabled,
#   the NSG rules won't be enforced on the private endpoint NIC itself.
#   The NSG still applies to other resources (if any) in the PE subnet.
#   This is an Azure platform behaviour, not a Terraform quirk.
# =============================================================================
resource "azurerm_network_security_group" "pe" {
  name                = "nsg-pe-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow all traffic from within the VNet to reach private endpoints.
  # AKS pods (in the AKS subnet) resolve service hostnames to private IPs
  # via Azure Private DNS zones, then connect here. This rule enables that.
  security_rule {
    name                       = "allow-vnet-to-private-endpoints"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Allow all VNet traffic to reach private endpoints. Required for AKS pods to connect to CosmosDB, Key Vault, ACR, etc."
  }
}

# =============================================================================
# NSG-SUBNET ASSOCIATIONS
#
# WHY is this a separate resource instead of inline in the subnet?
#
#   In azurerm 3.x, you could set network_security_group_id directly on the
#   azurerm_subnet resource. This was deprecated because it caused circular
#   dependency issues when the NSG and subnet were managed together.
#
#   azurerm_subnet_network_security_group_association is the clean solution:
#   it's a separate resource that Terraform can manage independently, allowing
#   NSGs to be updated without touching the subnet itself.
#
# WHY no NSG on the AppGW subnet?
#   Application Gateway v2 has specific NSG requirements:
#     - Allow inbound on ports 65200-65535 (AGW management/health traffic)
#     - Allow inbound from GatewayManager service tag
#   These rules are non-trivial and AGW deployment is out of scope for Week 1.
#   We create the NSG and association when we deploy AGW in a later week.
# =============================================================================

# Attach the AKS NSG to the AKS subnet.
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Attach the PE NSG to the private endpoint subnet.
resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}
