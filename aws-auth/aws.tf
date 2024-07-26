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
  name = "${var.app_prefix}-role"
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
            "${local.oidc_issuer_without_https}:sub" : "plugin-identity:${var.vault_namespace_id}:auth:${vault_auth_backend.aws.accessor}",
            "${local.oidc_issuer_without_https}:aud" : "${var.aws_audience}"
          }
        }
      },
    ]
  })
}


resource "aws_iam_policy" "vault_plugin_wif_policy" {
  name        = "${var.app_prefix}-policy"
  description = "Vault Plugin WIF policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeInstances",
          "iam:GetInstanceProfile",
          "iam:GetUser",
          "iam:GetRole"
        ],
        "Resource" : "*"
      },
      # AssumeRole permission for cross-account access
      # {
      #   "Effect" : "Allow",
      #   "Action" : [
      #     "sts:AssumeRole",
      #   ],
      #   "Resource" : "arn:aws:iam::${data.aws_caller_identity.target_account.account_id}:role/*"
      # }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "vault_plugin_wif_policy_attachment" {
  role       = aws_iam_role.vault_plugin_wif_role.name
  policy_arn = aws_iam_policy.vault_plugin_wif_policy.arn
}
