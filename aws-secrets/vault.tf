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
  path    = "sys/mounts/${vault_aws_secret_backend.aws.path}"
  version = 1
}


resource "vault_aws_secret_backend" "aws" {
  identity_token_ttl        = 60 * 5 # 5 minutes
  identity_token_audience   = var.aws_audience
  identity_token_key        = vault_identity_oidc_key.plugin_wif.id
  role_arn                  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vault-plugin-wif-role"
  default_lease_ttl_seconds = 60 * 30     # 30 minutes
  max_lease_ttl_seconds     = 60 * 60 * 2 # 2 hours
}




# resource "vault_aws_secret_backend_role" "role" {
#   backend         = vault_aws_secret_backend.aws.path
#   name            = "test"
#   credential_type = "assumed_role"

#   role_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/test"]
# }

# resource "vault_aws_secret_backend_role" "role2" {
#   backend         = vault_aws_secret_backend.aws.path
#   name            = "test2"
#   credential_type = "iam_user"
#   policy_arns     = ["arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"]
# }



