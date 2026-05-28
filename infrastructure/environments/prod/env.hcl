# =============================================================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# File: infrastructure/environments/prod/env.hcl
#
# TODO: Copy from dev/env.hcl and adjust values for production:
#   - environment   = "prod"
#   - network_octet = "2"   (prod VNet: 10.2.0.0/16)
#   - AppGW subnet should be /24 (not /27) for AGW v2 autoscaling
#   - Consider DDoS protection plan (significant cost — ~$2,944/month)
#   - Consider Availability Zone-aware AKS node pools
#
# Production differences from dev/staging:
#   - AKS: multi-AZ node pools (zone = [1, 2, 3])
#   - AKS: System node pool separate from user node pool
#   - Storage: GRS (geo-redundant) instead of LRS
#   - PostgreSQL: zone-redundant high availability
#   - CosmosDB: multi-region writes (if required)
#   - Key Vault: soft-delete with 90-day retention (already default in azurerm 4.x)
#   - Monitoring: alerting rules for CPU, memory, pod count thresholds
# =============================================================================

locals {
  # TODO: Uncomment and populate when setting up production environment
  # Production should NOT be deployed until:
  #   1. dev and staging are proven stable
  #   2. Security review is complete (see SECURITY_TESTS.md)
  #   3. Backup and DR strategy is documented

  # environment   = "prod"
  # location      = "eastus"
  # naming_prefix = "antkart"
  # network_octet = "2"
  # common_tags = {
  #   environment = "prod"
  #   project     = "antkart"
  #   managed_by  = "terraform"
  #   owner       = "sathish"
  # }
}
