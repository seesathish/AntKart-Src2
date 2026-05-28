# =============================================================================
# STAGING ENVIRONMENT CONFIGURATION
# File: infrastructure/environments/staging/env.hcl
#
# TODO: Copy from dev/env.hcl and adjust values for staging:
#   - environment   = "staging"
#   - network_octet = "1"   (staging VNet: 10.1.0.0/16)
#   - owner tag as appropriate
#
# Staging should mirror production configuration as closely as possible so
# that "it works in staging" is a reliable signal for "it works in prod".
# The main differences from prod are:
#   - Smaller AKS node SKUs (to save cost)
#   - Lower redundancy (LRS instead of GRS for storage)
#   - No DDoS protection plan
#   - Shorter backup retention periods
# =============================================================================

locals {
  # TODO: Uncomment and populate when setting up staging environment

  # environment   = "staging"
  # location      = "eastus"
  # naming_prefix = "antkart"
  # network_octet = "1"
  # common_tags = {
  #   environment = "staging"
  #   project     = "antkart"
  #   managed_by  = "terraform"
  #   owner       = "sathish"
  # }
}
