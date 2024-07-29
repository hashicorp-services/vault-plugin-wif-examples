provider "aws" {
}

locals {
  oidc_issuer_without_https = replace(local.oidc_base_url, "https://", "")
  oidc_base_url             = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer_url.issuer}/v1/identity/oidc/plugins" : "${vault_identity_oidc.issuer_url.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/plugins"
}

data "vault_namespace" "current" {}

data "aws_caller_identity" "current" {}

data "tls_certificate" "vault_oidc_issuer_certificate" {
  url          = var.public_oidc_issuer_url
  verify_chain = false
}

resource "aws_iam_openid_connect_provider" "vault_plugin_wif_provider" {
  url             = local.oidc_base_url
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
            "${local.oidc_issuer_without_https}:sub" : "plugin-identity:${var.vault_namespace_id}:secret:${data.vault_generic_secret.aws_secret_mount_details.data.accessor}",
            "${local.oidc_issuer_without_https}:aud" : "${var.aws_audience}"
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
        "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "vault_plugin_wif_policy_attachment" {
  role       = aws_iam_role.vault_plugin_wif_role.name
  policy_arn = aws_iam_policy.vault_plugin_wif_policy.arn
}

