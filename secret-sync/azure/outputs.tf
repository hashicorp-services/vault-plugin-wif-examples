output "secrets_sync_oidc_discovery_url" {
  description = "Secrets sync OIDC discovery document URL. This endpoint must be reachable by Azure."
  value       = "${local.oidc_base_url}/.well-known/openid-configuration"
}

output "wif_audience" {
  description = "Audience (aud) shared by the identity token, the OIDC key's allowed_client_ids, and the federated identity credential."
  value       = var.azure_audience
}

output "wif_application_client_id" {
  description = "Client ID of the Entra ID app registration Vault federates into through workload identity federation."
  value       = azuread_application.secrets_sync.client_id
}

output "expected_token_subject" {
  description = "The 'sub' claim Vault issues for this destination, matched by the federated identity credential's subject."
  value       = local.expected_subject
}

output "key_vault_name" {
  description = "Name of the Azure Key Vault that receives the synced secret."
  value       = azurerm_key_vault.secrets_sync.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault configured on the sync destination."
  value       = azurerm_key_vault.secrets_sync.vault_uri
}

output "destination_name" {
  description = "Name of the Vault Azure Key Vault sync destination."
  value       = vault_secrets_sync_azure_destination.this.name
}

output "synced_secret_sync_status" {
  description = "Sync status of the demo secret association (SYNCED once the secret reaches Azure Key Vault)."
  value       = [for m in vault_secrets_sync_association.demo.metadata : m.sync_status]
}

output "expected_azure_secret_name" {
  description = "Azure Key Vault secret name for the demo secret (synced by Vault), produced by the tenant's secret name template."
  value       = local.expected_azure_secret_name
}
