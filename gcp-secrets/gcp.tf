provider "google" {
  project = var.gcp_project_id
}

locals {
  oidc_base_url = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer_url.issuer}/v1/identity/oidc/plugins" : "${vault_identity_oidc.issuer_url.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/plugins"
}

data "vault_namespace" "current" {}

resource "random_id" "vault_plugin_wif_id" {
  byte_length = 2
}

resource "google_project_service" "services" {
  for_each           = toset(var.activate_apis)
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "vault_plugin_wif_pool" {
  workload_identity_pool_id = "${var.app_prefix}-pool-${random_id.vault_plugin_wif_id.hex}"
}

resource "google_iam_workload_identity_pool_provider" "vault_plugin_wif_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.vault_plugin_wif_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.app_prefix}-provider"
  attribute_mapping = {
    "google.subject"                 = "assertion.sub",
    "attribute.aud"                  = "assertion.aud[0]",
    "attribute.vault_accessor"       = "assertion.vaultproject.io.accessor",
    "attribute.vault_namespace_path" = "assertion.vaultproject.io.namespace_path",
    "attribute.vault_mount_path"     = "assertion.vaultproject.io.path",
  }
  oidc {
    issuer_uri        = local.oidc_base_url
    allowed_audiences = [local.identity_token_audience]
  }
  attribute_condition = "assertion.sub == \"plugin-identity:${var.vault_namespace_id}:secret:${vault_gcp_secret_backend.plugin_wif.accessor}\""
}


resource "google_service_account" "vault_plugin_wif" {
  account_id   = "${var.app_prefix}-sa-${random_id.vault_plugin_wif_id.hex}"
  display_name = "Vault plugin WIF Service Account"
}

resource "google_service_account_iam_member" "vault_plugin_wif_member" {
  service_account_id = google_service_account.vault_plugin_wif.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.vault_plugin_wif_pool.name}/subject/plugin-identity:${var.vault_namespace_id}:secret:${vault_gcp_secret_backend.plugin_wif.accessor}"
}


resource "google_project_iam_custom_role" "vault_plugin_wif_gcp_secret" {
  role_id     = "VaultGCPSecretsEngineRole"
  title       = "Vault GCP Secrets Engine Role"
  description = "A custom IAM role for Vault GCP secrets engine."
  permissions = var.vault_gcp_secret_permissions
}

resource "google_project_iam_member" "vault_plugin_wif_gcp_secret" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.vault_plugin_wif_gcp_secret.name
  member  = google_service_account.vault_plugin_wif.member
}
