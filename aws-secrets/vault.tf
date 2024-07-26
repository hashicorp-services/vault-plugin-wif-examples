provider "vault" {
  # address = var.vault_address
}

resource "vault_identity_oidc" "issuer_url" {
  issuer = var.public_oidc_issuer_url
}

resource "vault_identity_oidc_key" "plugin_wif" {
  name               = "plugin-wif-key"
  rotation_period    = 60 * 60 * 24 * 90 # 90 days
  verification_ttl   = 60 * 60 * 24      # 24 hours
  algorithm          = "RS256"
  allowed_client_ids = [var.aws_audience]
}

data "vault_generic_secret" "aws_secret_mount_details" {
  path    = "sys/mounts/${vault_aws_secret_backend.plugin_wif.path}"
  version = 1
}

resource "vault_aws_secret_backend" "plugin_wif" {
  identity_token_ttl        = 60 * 5 # 5 minutes
  identity_token_audience   = var.aws_audience
  identity_token_key        = vault_identity_oidc_key.plugin_wif.id
  role_arn                  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vault/${var.app_prefix}-role"
  default_lease_ttl_seconds = 60 * 30     # 30 minutes
  max_lease_ttl_seconds     = 60 * 60 * 2 # 2 hours
}

# resource "vault_aws_secret_backend_role" "iam_user" {
#   backend                  = vault_aws_secret_backend.plugin_wif.path
#   name                     = "iam"
#   credential_type          = "iam_user"
#   policy_arns              = ["arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"]
#   permissions_boundary_arn = data.aws_iam_policy.demo_user_permissions_boundary.arn
# }

# data "aws_iam_policy" "demo_user_permissions_boundary" {
#   name = "DemoUser"
# }

# resource "vault_aws_secret_backend_role" "assumed_role" {
#   backend         = vault_aws_secret_backend.plugin_wif.path
#   name            = "assume_role"
#   credential_type = "assumed_role"
#   role_arns       = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/test"]
# }
