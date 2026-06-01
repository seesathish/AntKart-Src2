# =============================================================================
# AKS MODULE — OUTPUTS
# File: infrastructure/modules/aks/outputs.tf
#
# Consumers:
#   - identity module:  needs oidc_issuer_url for federated_identity_credential.issuer
#   - Helm/kubectl:     needs cluster name + RG for `az aks get-credentials`
#   - operators:        node_resource_group is where Azure puts the VMs, NSGs,
#                       Load Balancers, public IPs — useful for cost analysis
#                       and ad-hoc lookups (you'll never write Terraform against
#                       this RG; AKS manages it).
# =============================================================================

output "id" {
  description = "Full resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Cluster name. Use with `az aks get-credentials --name <this>`."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  description = "Resource group containing the AKS object itself (not the node RG)."
  value       = azurerm_kubernetes_cluster.this.resource_group_name
}

output "node_resource_group" {
  description = <<-EOT
    The auto-created resource group that contains the actual node VMs,
    Load Balancers, public IPs, NSGs, and managed disks. AKS owns this RG —
    you should never put your own resources in it or modify resources in it
    via Terraform. Useful for cost analysis: filter Azure Cost Management
    by this RG name to see only AKS node-level spend.
    Format: "MC_<rg>_<cluster-name>_<region>".
  EOT
  value = azurerm_kubernetes_cluster.this.node_resource_group
}

output "oidc_issuer_url" {
  description = <<-EOT
    URL of the cluster's OIDC issuer (e.g.
    https://eastus.oic.prod-aks.azure.com/<tenant>/<guid>/).
    Pass this to the identity module as aks_oidc_issuer_url so federated
    identity credentials know which issuer to trust.

    This URL is publicly resolvable on purpose: Entra ID needs to fetch
    the JWKS from it to validate the service-account tokens projected into
    pods. It exposes signing keys only — no cluster contents.
  EOT
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity. Useful if you need to grant additional roles beyond AcrPull (e.g., Azure Disk CSI requires Contributor on certain resources)."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "kube_admin_config_raw" {
  description = <<-EOT
    Admin kubeconfig blob. SENSITIVE — contains cluster admin credentials.
    Normally you authenticate with `az aks get-credentials` which uses your
    user identity; this output is here for automation that needs a kubeconfig
    file directly. Don't print, log, or commit this value.
  EOT
  value     = azurerm_kubernetes_cluster.this.kube_admin_config_raw
  sensitive = true
}

output "host" {
  description = "API server URL. Useful for CI/CD pipelines that need to call kubectl with a separate auth method."
  value       = azurerm_kubernetes_cluster.this.kube_admin_config[0].host
  sensitive   = true
}
