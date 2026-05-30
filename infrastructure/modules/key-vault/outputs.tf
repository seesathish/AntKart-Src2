# =============================================================================
# KEY VAULT MODULE — OUTPUTS
# File: infrastructure/modules/key-vault/outputs.tf
#
# Consumers of these outputs:
#   - AKS module:  needs `id` to scope the "Key Vault Secrets User" role assignment
#                  for the AKS node managed identity
#                  needs `vault_uri` to configure the Secrets Store CSI Driver
#   - App configs: the vault_uri is what Azure SDKs use to connect programmatically
#   - CI/CD:       uses `name` in `az keyvault secret set` commands
# =============================================================================

output "id" {
  description = <<-EOT
    Full Azure Resource ID of the Key Vault.
    Used to scope RBAC role assignments:
      AKS managed identity → Key Vault Secrets User → this vault ID
    Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{name}
  EOT
  value = azurerm_key_vault.this.id
}

output "name" {
  description = <<-EOT
    Key Vault name (e.g., "kv-antkart-dev").
    Used in Azure CLI operations:
      az keyvault secret set --vault-name kv-antkart-dev --name my-secret --value my-value
      az keyvault secret show --vault-name kv-antkart-dev --name my-secret
  EOT
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = <<-EOT
    The vault's HTTPS URI (e.g., https://kv-antkart-dev.vault.azure.net/).
    Used by:
      - Azure Key Vault SDK: new SecretClient(vaultUri, credential)
      - Secrets Store CSI Driver: SecretProviderClass.spec.parameters.keyvaultName
        (uses the name, but the SDK uses the URI)
      - OpenID Connect token validation: some JWK endpoints reference vault URIs
  EOT
  value = azurerm_key_vault.this.vault_uri
}
