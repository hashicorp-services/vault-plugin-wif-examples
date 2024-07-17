provider "aws" {
}

locals {
  oidc_issuer_without_https = replace(var.public_oidc_issuer_url, "https://", "")
}

data "aws_caller_identity" "current" {
}

# Data source used to grab the TLS certificate for Terraform Cloud.
#
# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate
data "tls_certificate" "vault_oidc_issuer_certificate" {
  url          = var.public_oidc_issuer_url
  verify_chain = false
}

# Creates an OIDC provider which is restricted to
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
resource "aws_iam_openid_connect_provider" "vault_plugin_wif_provider" {
  url             = "${var.public_oidc_issuer_url}/v1/identity/oidc/plugins"
  client_id_list  = [var.aws_audience]
  thumbprint_list = [data.tls_certificate.vault_oidc_issuer_certificate.certificates[0].sha1_fingerprint]
}


resource "aws_iam_role" "vault_plugin_wif_role" {
  name = "vault-plugin-wif-role"
  path = "/vault/"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "${aws_iam_openid_connect_provider.vault_plugin_wif_provider.arn}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.oidc_issuer_without_https}/v1/identity/oidc/plugins:sub" : "plugin-identity:root:secret:${data.vault_generic_secret.aws_secret_mount_details.data.accessor}",
            "${local.oidc_issuer_without_https}/v1/identity/oidc/plugins:aud" : "${var.aws_audience}"
          }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "vault_plugin_wif_policy" {
  name        = "vault-plugin-wif-policy"
  description = "Vault Plugin WIF policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:AttachUserPolicy",
          "iam:CreateAccessKey",
          "iam:CreateUser",
          "iam:DeleteAccessKey",
          "iam:DeleteUser",
          "iam:DeleteUserPolicy",
          "iam:DetachUserPolicy",
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupsForUser",
          "iam:ListUserPolicies",
          "iam:PutUserPolicy",
          "iam:AddUserToGroup",
          "iam:RemoveUserFromGroup"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sts:AssumeRole",
        ],
        "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vault/*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "vault_plugin_wif_policy_attachment" {
  role       = aws_iam_role.vault_plugin_wif_role.name
  policy_arn = aws_iam_policy.vault_plugin_wif_policy.arn
}



