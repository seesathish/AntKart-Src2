# =============================================================================
# AKS MODULE — MAIN
# File: infrastructure/modules/aks/main.tf
#
# PURPOSE:
#   Provisions one Azure Kubernetes Service (AKS) cluster with:
#     - Two node pools: "system" (k8s components) + "user" (app workloads)
#     - Azure CNI networking on the existing AKS subnet
#     - OIDC issuer + Workload Identity ENABLED (replaces secret-based auth)
#     - Container Insights → existing Log Analytics workspace
#     - AcrPull role assignment so the kubelet can pull antkart-base + service
#       images from acrantkartdev.azurecr.io without secrets
#
# COST WARNING (read before terragrunt apply):
#   AKS is the SINGLE LARGEST cost driver in AntKart's dev environment.
#   At dev sizing (2× Standard_B2s nodes + Standard SKU Load Balancer +
#   Container Insights ingestion) this module costs roughly $80-100 USD/month
#   if left running 24/7. The destroy-when-idle pattern documented in
#   DevelopmentGuide §7.10 brings this to ~$0 — please use it.
#
# WHAT THIS MODULE DELIBERATELY DOES NOT DO:
#   - Deploy applications. That's Helm charts (charts/antkart-service/).
#   - Create per-service managed identities. Those live in the identity module
#     so the identity lifecycle is decoupled from the cluster lifecycle.
#     Destroying AKS does not destroy the managed identities or their role
#     assignments — only the federated-credential link is broken.
#   - Configure private endpoints for the API server. AntKart dev uses the
#     public AKS API endpoint (free tier limitation, also simpler for laptop
#     access). Production would use Private AKS + bastion or VPN.
# =============================================================================

# -----------------------------------------------------------------------------
# AZURE KUBERNETES SERVICE CLUSTER
#
# DESIGN DECISIONS (full rationale in ADR-015):
#
# sku_tier = "Free"
#   The Free tier has NO SLA on the API server (best-effort 99.5% in practice).
#   The Standard tier costs $0.10/hr (~$73/month) and provides a 99.95% SLA.
#   For a dev/learning cluster this is pure waste. Production environments
#   should switch to "Standard". This is a deliberate per-environment tier
#   choice — a Well-Architected Framework "cost optimization" pillar example.
#
# kubernetes_version = unspecified (Azure picks the default supported version)
#   We pin the version through the AKS module's default Azure-recommended
#   version rather than hardcoding a number that goes stale. Upgrades will
#   be a deliberate Week 11+ activity.
#
# automatic_channel_upgrade = "patch"
#   Auto-applies patch-level Kubernetes upgrades (1.30.5 → 1.30.6) during
#   maintenance windows. Catches CVE fixes without manual cycles. Does NOT
#   apply minor upgrades (1.30 → 1.31) which would need code review.
#
# oidc_issuer_enabled + workload_identity_enabled
#   These two flags together make Workload Identity federation possible.
#   They:
#     1. Expose a public OIDC issuer URL on the cluster:
#        https://eastus.oic.prod-aks.azure.com/<tenant>/<guid>/
#     2. Project a short-lived service-account JWT into each pod's filesystem
#        when the pod's k8s SA carries the `azure.workload.identity/client-id`
#        annotation and the pod template carries `azure.workload.identity/use=true`.
#     3. That JWT is exchanged at Entra ID for an Azure access token via the
#        federated credential we configure in the identity module (Task 3).
#   Both flags are FREE — they enable a feature, they don't add resources.
#
# role_based_access_control_enabled = true (the default; left implicit)
#   AKS RBAC is on by default. Adding Azure AD integration would let users
#   authenticate to kubectl with their Entra identity — out of scope for now;
#   we use the admin kubeconfig from `az aks get-credentials`.
# -----------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name

  # See block comment above. Production sets this to "Standard".
  sku_tier = "Free"

  # Pin patch-level auto-upgrades. Minor upgrades remain manual.
  # NOTE: this argument was renamed `automatic_channel_upgrade` → `automatic_upgrade_channel`
  # in AzureRM 4.x. We're on 4.x via root.hcl's `~> 4.0` constraint.
  automatic_upgrade_channel = "patch"

  # The two Workload Identity prerequisites. See block comment above.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ---------------------------------------------------------------------------
  # SYSTEM NODE POOL
  #
  # The "default_node_pool" in terraform terms IS the system pool — AKS treats
  # this first pool as the place where critical addons (CoreDNS, metrics-server,
  # Azure CNI, Container Insights agent, konnectivity) get scheduled.
  #
  # only_critical_addons_enabled = true
  #   This applies the taint `CriticalAddonsOnly=true:NoSchedule` to every node
  #   in this pool. App pods (which don't carry the matching toleration) won't
  #   land here. Result: clean separation of system vs app workloads. If the
  #   user pool fills up or scales down, the system pool stays healthy and
  #   keeps DNS / log shipping / metrics running.
  #
  # auto_scaler 1 → 2:
  #   One node is enough for CoreDNS + metrics-server + Azure CNI + the
  #   Container Insights agent during normal operation. The +1 headroom is for
  #   when k8s drains the node for upgrades or AKS rotates underlying VM SKUs.
  #
  # VM size: Standard_B2s
  #   Burstable B-series: 2 vCPU, 4 GB RAM, ~$31/month per node.
  #   DEV CHOICE — production would use Standard_D4s_v5 or larger for
  #   predictable steady-state CPU, no burst credits to manage, and better
  #   isolation. The destroy-when-idle pattern documented in DevelopmentGuide
  #   §7.10 makes the burstable-credit concern irrelevant for dev.
  # ---------------------------------------------------------------------------
  default_node_pool {
    name = "system"

    # System pool taint via this flag — see block comment above.
    only_critical_addons_enabled = true

    vm_size              = var.system_node_vm_size
    orchestrator_version = var.kubernetes_version

    # Autoscaler bounds.
    # NOTE: renamed `enable_auto_scaling` → `auto_scaling_enabled` in AzureRM 4.x.
    auto_scaling_enabled = true
    min_count           = var.system_node_min_count
    max_count           = var.system_node_max_count

    # Place this pool in the AKS subnet (Azure CNI — one IP per pod).
    vnet_subnet_id = var.vnet_subnet_id

    # OS disk: 30 GiB ephemeral is enough for OS + container layers. Larger
    # disks cost more and provide no benefit for stateless workloads.
    os_disk_size_gb = 30
    os_disk_type    = "Ephemeral"

    tags = var.tags
  }

  # ---------------------------------------------------------------------------
  # CLUSTER IDENTITY (system-assigned)
  #
  # The CONTROL PLANE needs an Azure identity so it can:
  #   - Manage Load Balancers, public IPs, network security groups for services
  #   - Mount Azure Disks / Files as Kubernetes volumes
  #   - Pull from ACR (when used WITH the AcrPull role assignment below)
  #
  # System-assigned vs user-assigned:
  #   System-assigned is created and destroyed with the cluster — simpler.
  #   User-assigned is independent and survives cluster recreation — needed if
  #   you need RBAC grants outside the cluster's resource group to persist
  #   across cluster rebuilds. For dev, system-assigned is fine.
  #
  # SEPARATE FROM the kubelet identity:
  #   AKS automatically creates a second identity ("kubelet identity") on every
  #   node, used for pulling images and accessing per-pod resources. That's the
  #   identity that needs AcrPull — see the role assignment below.
  # ---------------------------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # NETWORK PROFILE — Azure CNI
  #
  # network_plugin = "azure" (Azure CNI):
  #   Every pod gets a real VNet IP from the AKS subnet (10.0.0.0/22).
  #   Pros: direct pod IP routing, no NAT, NSG rules apply to pod traffic,
  #         pods can be addressed from other VNet resources (e.g., private
  #         endpoints for CosmosDB and Service Bus work without proxy hops).
  #   Cons: subnet IPs are consumed per-pod — with 30 pods/node ceiling and
  #         /22 = 1019 usable IPs, the subnet caps at ~33 nodes worth of pods.
  #         For dev (2-5 nodes, 30-150 pods) this is plenty of headroom.
  #
  # Alternative not used: kubenet (1 IP per node, pod IPs NAT'd). Cheaper on
  # subnet IPs but loses NSG visibility on pod traffic and doesn't let pods
  # consume Azure private endpoints directly. Azure CNI is the production
  # default for any cluster integrating with Azure PaaS.
  #
  # network_policy = "calico":
  #   Enables NetworkPolicy resources. Even though we don't use them in Week 7,
  #   enabling at cluster creation is required — you cannot add NetworkPolicy
  #   to an existing AKS cluster without rebuilding it. Future-proofing.
  #
  # load_balancer_sku = "standard" is the only option for new clusters.
  # service_cidr / dns_service_ip: cluster-internal address space for k8s
  # Services (ClusterIP). Must NOT overlap the VNet (10.0.0.0/16). 10.100.0.0/16
  # is well outside our VNet ranges.
  # ---------------------------------------------------------------------------
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "10.100.0.0/16"
    dns_service_ip    = "10.100.0.10"
  }

  # ---------------------------------------------------------------------------
  # CONTAINER INSIGHTS (OMS Agent) → Log Analytics
  #
  # Wires the AKS Container Insights addon to the existing Log Analytics
  # workspace (created by the log-analytics module in Week 5). This is what
  # makes container stdout/stderr, k8s events, and node metrics queryable
  # in Azure Monitor and Container Insights workbooks.
  #
  # Cost note: log ingestion is charged per GB. AntKart dev ingests perhaps
  # 100-500 MB/day — well within trivial cost. Production with verbose logs
  # at scale can ingest tens of GB/day. Watch this if you crank verbosity.
  #
  # msi_auth_for_monitoring_enabled = true: the OMS agent uses the AKS
  # managed identity to push logs (no shared-key auth, no certificate to
  # rotate). Modern best practice.
  # ---------------------------------------------------------------------------
  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags

  # Cluster-level lifecycle: ignore node_count changes that come from the
  # autoscaler (Terraform should not fight cluster-autoscaler). Pinning
  # tags here so they're not nuked on plan-replace if the AKS provider
  # adds default tags.
  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      microsoft_defender, # avoid drift if Defender is enabled outside terraform
    ]
  }
}

# -----------------------------------------------------------------------------
# USER NODE POOL — application workloads
#
# WHY A SEPARATE POOL (not just upsizing the system pool)?
#   1. Independent scaling. App pods autoscale on their own metrics without
#      tripping system-pool capacity. System pool can stay tiny and stable.
#   2. Independent VM SKU. Production could put system on D-series (steady)
#      and user on B-series (burstable) or vice versa.
#   3. Cordoning during upgrades. We can drain the user pool, run app
#      maintenance, and bring it back without disturbing CoreDNS pods.
#   4. Spot eligibility. Future cost optimization: make user pool spot-VM-only
#      while keeping system pool on regular VMs. Spot is risky for kube-system.
#
# No taint here — pods with no tolerations land naturally on this pool because
# the system pool's CriticalAddonsOnly taint excludes them.
# -----------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id

  vm_size              = var.user_node_vm_size
  orchestrator_version = var.kubernetes_version

  # NOTE: renamed `enable_auto_scaling` → `auto_scaling_enabled` in AzureRM 4.x.
  auto_scaling_enabled = true
  min_count            = var.user_node_min_count
  max_count            = var.user_node_max_count

  vnet_subnet_id  = var.vnet_subnet_id
  os_disk_size_gb = 30
  os_disk_type    = "Ephemeral"

  # mode = "User" makes this pool selectable for app workloads. The system
  # pool is mode = "System" implicitly via only_critical_addons_enabled = true.
  mode = "User"

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count] # don't fight the autoscaler
  }
}

# -----------------------------------------------------------------------------
# RBAC — AcrPull on the registry for the AKS kubelet identity
#
# WHY THIS IS NEEDED:
#   When AKS schedules a pod, the kubelet on the chosen node pulls the
#   container image. If the image is in ACR (acrantkartdev.azurecr.io/...),
#   the kubelet's identity must have AcrPull on that registry — otherwise:
#     ImagePullBackOff → "401 Unauthorized" → pod stuck in Pending forever.
#
# WHY kubelet_identity, not the cluster identity?
#   AKS creates TWO identities:
#     - Cluster (control-plane) identity → manages Azure resources outside
#       the cluster (Load Balancers, disks, NSGs)
#     - Kubelet identity                 → runs ON the node, pulls images
#   AcrPull goes on the kubelet identity. This is the most common AKS gotcha:
#   people grant AcrPull to the cluster identity, image pulls still fail.
#
# kubelet_identity[0].object_id:
#   Terraform reads this after the cluster is created. Because of this read,
#   the role assignment has an implicit dependency on the cluster being fully
#   created (not just planned).
#
# Scoping to the ACR's resource ID:
#   The role is scoped to ONE registry, not the subscription. Tightest grant
#   that still works — principle of least privilege.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true # avoid eventual-consistency races with Entra
}
