# Module: networking

Creates the complete network foundation for one AntKart environment: a Virtual
Network with three purpose-built subnets and Network Security Groups enforcing
a default-deny posture.

## Network topology

```
VNet: vnet-antkart-{env}  (10.{octet}.0.0/16)
│
├── snet-aks-antkart-{env}    10.{octet}.0.0/22    ← AKS nodes + pods
│   └── NSG: nsg-aks-antkart-{env}
│         Allow: VNet inbound, AzureLoadBalancer inbound
│         Deny:  everything else (explicit rule + implicit default)
│
├── snet-pe-antkart-{env}     10.{octet}.4.0/24    ← Private endpoints
│   └── NSG: nsg-pe-antkart-{env}
│         Allow: VNet inbound
│         Deny:  everything else (implicit default)
│
└── snet-appgw-antkart-{env}  10.{octet}.5.0/27    ← Application Gateway (reserved)
    └── (NSG added when AGW is deployed)
```

## Why three subnets?

Azure requires certain resources to be in dedicated or appropriately sized subnets:

| Subnet | Resource | Why dedicated |
|--------|----------|---------------|
| `snet-aks` | AKS node pool + pods (Azure CNI) | Pods get real VNet IPs — needs /22 minimum for growth |
| `snet-pe` | Private endpoints for PaaS services | Network policy must be "Disabled" for PEs to function |
| `snet-appgw` | Application Gateway v2 | AGW requires a completely dedicated subnet |

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name` | string | yes | VNet name. Format: `vnet-<project>-<environment>` |
| `location` | string | yes | Azure region |
| `resource_group_name` | string | yes | Resource group from RG module output |
| `address_space` | list(string) | yes | VNet CIDR, e.g. `["10.0.0.0/16"]` |
| `subnet_prefixes` | object | yes | CIDRs for aks, pe, appgw subnets |
| `tags` | map(string) | no | Tags inherited from env.hcl |

## Outputs

| Name | Description |
|------|-------------|
| `vnet_id` | VNet Resource ID |
| `vnet_name` | VNet name |
| `aks_subnet_id` | AKS subnet ID → pass to AKS node pool |
| `pe_subnet_id` | Private endpoint subnet ID → pass to all azurerm_private_endpoint |
| `appgw_subnet_id` | AppGW subnet ID → pass to Application Gateway |
| `aks_nsg_id` | AKS NSG ID |
| `pe_nsg_id` | PE NSG ID |

## CIDR sizing guide

| Environment | VNet | AKS subnet | PE subnet | AppGW subnet |
|-------------|------|------------|-----------|--------------|
| dev | 10.0.0.0/16 | 10.0.0.0/22 | 10.0.4.0/24 | 10.0.5.0/27 |
| staging | 10.1.0.0/16 | 10.1.0.0/22 | 10.1.4.0/24 | 10.1.5.0/27 |
| prod | 10.2.0.0/16 | 10.2.0.0/22 | 10.2.4.0/24 | 10.2.5.0/24 |

Prod AppGW uses /24 because AGW v2 can scale to 125 instances.

## AKS subnet sizing — why /22?

With Azure CNI (the network plugin AntKart uses), **every pod gets a real VNet IP**.
A cluster with 3 nodes × 30 pods/node = 90 IPs consumed immediately.

A /24 subnet (256 IPs, minus 5 Azure reserved = 251 usable) fills up fast.
A /22 (1,024 IPs) gives room for autoscaling without subnet redesign.

**Rule of thumb:** AKS subnet size = (max nodes × max pods/node) × 1.5 headroom.

## Example usage

```hcl
terraform {
  source = "../../../modules/networking"
}

dependency "resource_group" {
  config_path = "../resource-group"
}

inputs = {
  name                = "vnet-antkart-dev"
  location            = "eastus"
  resource_group_name = dependency.resource_group.outputs.name
  address_space       = ["10.0.0.0/16"]
  subnet_prefixes = {
    aks   = "10.0.0.0/22"
    pe    = "10.0.4.0/24"
    appgw = "10.0.5.0/27"
  }
  tags = {
    environment = "dev"
    project     = "antkart"
    managed_by  = "terraform"
  }
}
```
