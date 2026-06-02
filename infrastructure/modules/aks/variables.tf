# =============================================================================
# AKS MODULE — VARIABLES
# File: infrastructure/modules/aks/variables.tf
#
# Every variable here is consumed by the dev (or staging/prod) wiring file
# at environments/<env>/aks/terragrunt.hcl. Production sizing values will
# differ — that's the point of having them as variables.
# =============================================================================

variable "name" {
  description = "AKS cluster name (e.g. aks-antkart-dev). Also used as the dns_prefix."
  type        = string
}

variable "location" {
  description = "Azure region. Must match the resource group and subnet."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will host the cluster object. AKS also creates a 'node resource group' separately — see outputs.node_resource_group."
  type        = string
}

variable "tags" {
  description = "Tags applied to the cluster and node pools."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vnet_subnet_id" {
  description = "Resource ID of the AKS subnet (10.0.0.0/22 in dev). Both node pools attach here. Comes from the networking module's aks_subnet_id output."
  type        = string
}

# -----------------------------------------------------------------------------
# ACR (for AcrPull role assignment)
# -----------------------------------------------------------------------------
variable "acr_id" {
  description = "Resource ID of the Azure Container Registry. The cluster's kubelet identity is granted AcrPull on this registry so it can pull antkart-base and service images."
  type        = string
}

# -----------------------------------------------------------------------------
# Log Analytics (for Container Insights)
# -----------------------------------------------------------------------------
variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace to receive Container Insights data. Comes from the log-analytics module's workspace_id output."
  type        = string
}

# -----------------------------------------------------------------------------
# Kubernetes version
# -----------------------------------------------------------------------------
variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version (e.g. "1.30"). Leave null to use AKS's default supported
    version at apply time. Pinning is a deliberate choice — staging should
    upgrade first, then prod, with dev usually leading.
  EOT
  type    = string
  default = null
}

# -----------------------------------------------------------------------------
# System node pool sizing
#
# DEV defaults below match ADR-015. Production overrides via terragrunt inputs.
# -----------------------------------------------------------------------------
variable "system_node_vm_size" {
  description = <<-EOT
    VM SKU for the system node pool.

    Dev default: Standard_D2ds_v4 (~$70/mo/node, x86, 2 vCPU, 8 GB RAM,
    75 GiB local NVMe temp disk — supports our 30 GB ephemeral OS disk).

    HISTORICAL NOTE: The original ADR-015 choice was Standard_B2s (~$31/mo,
    burstable). The Azure subscription used for AntKart blocks Standard_B2s
    in eastus via tenant policy — only D-series, Bsv2-ARM64, and a few
    others are allowed. First substitution Standard_D2s_v4 failed because
    the Dsv4 family has NO local temp disk (Microsoft split Dv4 into
    Dsv4 = no-temp = cheaper-at-scale, and Ddsv4 = with-temp = supports
    ephemeral OS). The extra 'd' in Ddsv4 = "with local disk".
    Standard_D2ds_v4 is the right choice: same price as D2s_v4, with 75 GiB
    NVMe that supports ephemeral OS at our 30 GB size.

    ARM64 (Standard_b2ps_v2 ~$28) would have kept the burstable cost
    profile but required multi-arch image builds — deferred.

    Prod recommendation: Standard_D4s_v5 or larger for predictable performance.
  EOT
  type    = string
  default = "Standard_D2ds_v4"
}

variable "system_node_min_count" {
  description = "Minimum nodes in the system pool. Setting 1 is safe because CoreDNS and metrics-server tolerate single-node operation; autoscaler adds a second if scheduling pressure appears."
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum nodes in the system pool. 2 is enough for upgrade drains and brief load spikes on kube-system pods."
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# User node pool sizing
# -----------------------------------------------------------------------------
variable "user_node_vm_size" {
  description = <<-EOT
    VM SKU for app workloads.

    Dev default: Standard_D2s_v4 (~$70/mo/node, x86, 2 vCPU, 8 GB RAM).

    See the HISTORICAL NOTE on system_node_vm_size — the subscription policy
    blocks Standard_B2s in eastus, so the original burstable choice isn't
    available. D2s_v4 is the closest viable substitute that keeps amd64
    images working without rebuilds.

    Prod recommendation: Standard_D4s_v5 or larger.
  EOT
  type    = string
  default = "Standard_D2ds_v4"
}

variable "user_node_min_count" {
  description = "Minimum nodes in the user pool. 1 is enough for Week 7 (one service deployed)."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum nodes in the user pool. 3 is enough for the full 8-service fleet at dev resource requests (~150 MiB CPU + 256 MiB memory per pod)."
  type        = number
  default     = 3
}
