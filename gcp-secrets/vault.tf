provider "vault" {
  # address = var.vault_address
}

locals {
  identity_token_audience = "https://iam.googleapis.com/${google_iam_workload_identity_pool.vault_plugin_wif_pool.name}/providers/${var.app_prefix}-provider"
}

resource "vault_identity_oidc" "issuer_url" {
  issuer = var.public_oidc_issuer_url
}

resource "vault_identity_oidc_key" "plugin_wif" {
  name               = "plugin-wif-key"
  rotation_period    = 60 * 60 * 24 * 90 # 90 days
  verification_ttl   = 60 * 60 * 24      # 24 hours
  algorithm          = "RS256"
  allowed_client_ids = [local.identity_token_audience]
}

resource "vault_gcp_secret_backend" "plugin_wif" {
  identity_token_key        = vault_identity_oidc_key.plugin_wif.id
  identity_token_ttl        = 60 * 30 # 30 minutes
  identity_token_audience   = local.identity_token_audience
  service_account_email     = "${var.app_prefix}-sa-${random_id.vault_plugin_wif_id.hex}@${var.gcp_project_id}.iam.gserviceaccount.com"
  default_lease_ttl_seconds = 60 * 30     # 30 minutes
  max_lease_ttl_seconds     = 60 * 60 * 2 # 2 hours
}

# resource "vault_gcp_secret_roleset" "token_roleset" {
#   backend      = vault_gcp_secret_backend.plugin_wif.path
#   roleset      = "project_viewer_token"
#   secret_type  = "access_token"
#   project      = var.gcp_project_id
#   token_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

#   binding {
#     resource = "//cloudresourcemanager.googleapis.com/projects/${var.gcp_project_id}"
#     roles = [
#       "roles/viewer",
#     ]
#   }
# }
