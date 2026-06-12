output "secrets_sync_oidc_discovery_url" {
  description = "Secrets sync OIDC discovery document URL. This endpoint must be reachable by GCP."
  value       = "${local.oidc_base_url}/.well-known/openid-configuration"
}

output "wif_audience" {
  description = "Audience (aud) shared by the identity token, the GCP workload identity pool provider, and the OIDC key's allowed_client_ids."
  value       = local.gcp_audience
}

output "wif_service_account_email" {
  description = "Email of the service account Vault impersonates through workload identity federation."
  value       = google_service_account.secrets_sync.email
}

output "wif_pool_provider_name" {
  description = "Full resource name of the workload identity pool provider that federates Vault identity tokens."
  value       = google_iam_workload_identity_pool_provider.secrets_sync.name
}

output "wif_project_id" {
  description = "Project hosting the workload identity pool and provider (the Vault trust anchor)."
  value       = local.wif_project
}

output "tenant_project_id" {
  description = "Tenant resource project holding the service account, custom role, and synced secrets."
  value       = var.gcp_project_id
}

output "expected_token_subject" {
  description = "The 'sub' claim Vault issues for this destination, matched by the pool provider's attribute_condition and the service account impersonation binding."
  value       = local.expected_subject
}

output "destination_name" {
  description = "Name of the Vault GCP Secret Manager sync destination."
  value       = vault_secrets_sync_gcp_destination.this.name
}

output "synced_secret_sync_status" {
  description = "Sync status of the demo secret association (SYNCED once the secret reaches GCP Secret Manager)."
  value       = [for m in vault_secrets_sync_association.demo.metadata : m.sync_status]
}

output "expected_gcp_secret_name" {
  description = "GCP Secret Manager secret ID for the demo secret (created and synced by Vault), produced by the tenant's secret name template."
  value       = local.expected_gcp_secret_name
}
