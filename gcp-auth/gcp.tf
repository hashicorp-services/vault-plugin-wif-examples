provider "google" {
  project = var.gcp_project_id
}

resource "random_id" "vault_plugin_wif_id" {
  byte_length = 2
}

resource "google_project_service" "services" {
  for_each           = toset(var.activate_apis)
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "vault_plugin_wif_pool" {
  workload_identity_pool_id = "vault-plugin-wif-pool-${random_id.vault_plugin_wif_id.hex}"
}

resource "google_iam_workload_identity_pool_provider" "vault_plugin_wif_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.vault_plugin_wif_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "vault-plugin-wif-provider"
  attribute_mapping = {
    "google.subject"                 = "assertion.sub",
    "attribute.aud"                  = "assertion.aud[0]",
    "attribute.vault_accessor"       = "assertion.vaultproject.io.accessor",
    "attribute.vault_namespace_path" = "assertion.vaultproject.io.namespace_path",
    "attribute.vault_mount_path"     = "assertion.vaultproject.io.path",
  }
  oidc {
    issuer_uri        = "${var.public_oidc_issuer_url}/v1/identity/oidc/plugins"
    allowed_audiences = [local.identity_token_audience]
  }
  attribute_condition = "assertion.sub == \"plugin-identity:root:auth:${vault_gcp_auth_backend.gcp.accessor}\""
}


resource "google_service_account" "vault_plugin_wif" {
  account_id   = "vault-plugin-wif-sa-${random_id.vault_plugin_wif_id.hex}"
  display_name = "Vault plugin WIF Service Account"
}

resource "google_service_account_iam_member" "vault_plugin_wif_member" {
  service_account_id = google_service_account.vault_plugin_wif.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.vault_plugin_wif_pool.name}/subject/plugin-identity:root:auth:${vault_gcp_auth_backend.gcp.accessor}"
}


resource "google_project_iam_custom_role" "vault_gcp_auth" {
  role_id     = "VaultGCPAuthRole"
  title       = "Vault GCP Auth Role"
  description = "A custom IAM role for Vault GCP auth method."
  permissions = var.vault_gcp_auth_permissions
}

resource "google_project_iam_member" "vault_plugin_wif" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.vault_gcp_auth.name
  member  = google_service_account.vault_plugin_wif.member
}
