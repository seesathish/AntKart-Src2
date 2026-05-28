# =============================================================================
# NETWORKING MODULE — INPUT VARIABLES
# File: infrastructure/modules/networking/variables.tf
# =============================================================================

variable "name" {
  type        = string
  description = <<-EOT
    The Virtual Network name. Convention: vnet-<project>-<environment>
    Example: vnet-antkart-dev

    The module derives all child resource names from this:
      vnet-antkart-dev  →  snet-aks-antkart-dev
                           snet-pe-antkart-dev
                           snet-appgw-antkart-dev
                           nsg-aks-antkart-dev
                           nsg-pe-antkart-dev
    This guarantees naming consistency without requiring separate variables
    for every child resource.
  EOT
}

variable "location" {
  type        = string
  description = "Azure region. Must match the resource group's region — networking resources cannot span regions."
}

variable "resource_group_name" {
  type        = string
  description = <<-EOT
    The resource group to deploy the VNet and all networking resources into.
    Consumed from the resource-group module's output:
      dependency.resource_group.outputs.name
  EOT
}

variable "address_space" {
  type        = list(string)
  description = <<-EOT
    The address space for the Virtual Network, in CIDR notation.
    This is the overall IP range from which all subnets are carved.

    AntKart VNet addressing plan (per environment):
      dev:     ["10.0.0.0/16"]   →  65,536 addresses
      staging: ["10.1.0.0/16"]   →  65,536 addresses
      prod:    ["10.2.0.0/16"]   →  65,536 addresses

    WHY a /16 per environment?
      Large enough for all future subnets (AKS nodes, pods, private endpoints,
      app gateway, etc.) while still fitting neatly in the 10.x.x.x private
      space. The network_octet in env.hcl controls which /16 block each
      environment gets.

    Multiple CIDR blocks are allowed (e.g., for hybrid connectivity scenarios)
    but AntKart uses one per environment to keep it simple.
  EOT
}

variable "subnet_prefixes" {
  type = object({
    aks   = string
    pe    = string
    appgw = string
  })
  description = <<-EOT
    CIDR blocks for each of the three subnets. Must all fall within address_space.

    AntKart subnet sizing rationale:
    ┌──────────────┬──────────────────┬────────────────────────────────────────────┐
    │ Subnet       │ Dev CIDR         │ Why this size                              │
    ├──────────────┼──────────────────┼────────────────────────────────────────────┤
    │ aks          │ 10.0.0.0/22      │ 1,024 IPs. AKS needs IPs for both nodes   │
    │              │                  │ AND pods (kubenet: 1 IP/node + CIDR/node;  │
    │              │                  │ Azure CNI: 1 IP/pod). /22 gives room to    │
    │              │                  │ scale. A /24 (256 IPs) is too small for    │
    │              │                  │ a real workload.                           │
    ├──────────────┼──────────────────┼────────────────────────────────────────────┤
    │ pe           │ 10.0.4.0/24      │ 256 IPs. Each private endpoint (CosmosDB, │
    │              │                  │ Key Vault, ACR, Service Bus) consumes one  │
    │              │                  │ private IP. 256 is more than enough.       │
    ├──────────────┼──────────────────┼────────────────────────────────────────────┤
    │ appgw        │ 10.0.5.0/27      │ 32 IPs. Azure Application Gateway v2      │
    │              │                  │ requires a dedicated /24 minimum in prod   │
    │              │                  │ (for autoscaling). /27 is fine for dev     │
    │              │                  │ where we reserve the subnet but don't      │
    │              │                  │ deploy AGW yet.                            │
    └──────────────┴──────────────────┴────────────────────────────────────────────┘

    Example:
      subnet_prefixes = {
        aks   = "10.0.0.0/22"
        pe    = "10.0.4.0/24"
        appgw = "10.0.5.0/27"
      }
  EOT
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all networking resources (VNet, subnets, NSGs). Inherit from env.hcl common_tags."
  default     = {}
}
