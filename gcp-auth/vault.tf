locals {
  identity_token_audience = "https://iam.googleapis.com/${google_iam_workload_identity_pool.vault_plugin_wif_pool.name}/providers/vault-plugin-wif-provider"
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


resource "vault_gcp_auth_backend" "gcp" {
  identity_token_key      = vault_identity_oidc_key.plugin_wif.id
  identity_token_ttl      = 60 * 30 # 30 minutes
  identity_token_audience = local.identity_token_audience
  service_account_email   = "vault-plugin-wif-sa-${random_id.vault_plugin_wif_id.hex}@${var.gcp_project_id}.iam.gserviceaccount.com"
  tune {
    default_lease_ttl = "30m"
    max_lease_ttl     = "2h"
    token_type        = "default-service"
  }
}

resource "vault_gcp_auth_backend_role" "gcp_example" {
  backend                = vault_gcp_auth_backend.gcp.path
  role                   = "test"
  type                   = "iam"
  bound_service_accounts = ["*"]
  max_jwt_exp            = "3600"
  #   add_group_aliases = true
  #   bound_projects = [var.gcp_project_id]

  # Don't need this, policy will be attached to the identity.  
  #   token_policies = [vault_policy.demo.name] 
}



resource "vault_gcp_auth_backend_role" "gcp_example3" {
  backend = vault_gcp_auth_backend.gcp.path
  role    = "gce"
  type    = "gce"
  #   bound_service_accounts = [google_service_account.vault_plugin_wif.email]
  # add_group_aliases = true
  # bound_projects    = [var.gcp_project_id]
  bound_zones = ["europe-west2-a"]
}
