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

resource "vault_auth_backend" "plugin_wif" {
  type               = "aws"
  identity_token_key = vault_identity_oidc_key.plugin_wif.id

  tune {
    default_lease_ttl = "30m"
    max_lease_ttl     = "2h"
  }
}

resource "vault_aws_auth_backend_client" "plugin_wif" {
  backend                 = vault_auth_backend.plugin_wif.path
  identity_token_audience = var.aws_audience
  role_arn                = aws_iam_role.vault_plugin_wif_role.arn
  identity_token_ttl      = 60 * 5 # 5 minutes
}


# resource "vault_aws_auth_backend_role" "plugin_wif" {
#   backend                  = vault_auth_backend.plugin_wif.path
#   role                     = "test"
#   auth_type                = "iam"
#   bound_iam_principal_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"]
#   token_ttl                = 1800
#   token_max_ttl            = 3600
#   token_policies           = ["aws-auth-policy"]
# }
