provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "vault_namespace" "current" {}

# TLS cert of the issuer endpoint for the IAM OIDC provider thumbprint.
data "tls_certificate" "issuer" {
  url          = var.public_oidc_issuer_url
  verify_chain = false
}

locals {
  # Secrets sync uses a dedicated issuer path (identity/oidc/secrets-sync).
  oidc_base_url = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer.issuer}/v1/identity/oidc/secrets-sync" : "${vault_identity_oidc.issuer.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/secrets-sync"

  oidc_issuer_no_scheme = replace(local.oidc_base_url, "https://", "")

  # Token audience (recipient). Defaults to the issuer host+path; pinned by the
  # OIDC provider client ID and the role trust policy.
  aws_audience = var.aws_audience != "" ? var.aws_audience : local.oidc_issuer_no_scheme

  # Per-tenant resource names, all derived from var.tenant_id.
  name_prefix          = "${var.tenant_id}-secrets-sync"                # IAM role/policy and OIDC key/role
  destination_name     = "${var.tenant_id}-aws-sm"                      # Vault sync destination (drives the token sub)
  kv_mount_path        = "${var.tenant_id}-kv"                          # the tenant's KV v2 mount
  secret_name_template = "vault-${var.tenant_id}-{{ .SecretBaseName }}" # synced secret name in AWS Secrets Manager

  # IAM policy wildcard scope. Trailing hyphen stops "app1" matching "app10".
  secret_resource_prefix = "vault-${var.tenant_id}-"

  # Token sub: secrets-sync:<namespace>:<type>:<name> (root ns => "root"); pinned
  # by the IAM role trust policy.
  namespace_segment = data.vault_namespace.current.id == "/" ? "root" : data.vault_namespace.current.id
  expected_subject  = "secrets-sync:${local.namespace_segment}:aws-sm:${local.destination_name}"

  # Tags applied to every taggable resource.
  common_tags = {
    "managed-by" = "terraform-vault-secrets-sync"
    "tenant"     = var.tenant_id
  }
}

# Register Vault's secrets sync issuer as an IAM OIDC identity provider.
resource "aws_iam_openid_connect_provider" "vault_secrets_sync" {
  url             = local.oidc_base_url
  client_id_list  = [local.aws_audience]
  thumbprint_list = [data.tls_certificate.issuer.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

# Role Vault assumes via AssumeRoleWithWebIdentity; trust policy pins the audience
# and exact token sub.
resource "aws_iam_role" "secrets_sync" {
  name = "${local.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.vault_secrets_sync.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_no_scheme}:aud" = local.aws_audience
            "${local.oidc_issuer_no_scheme}:sub" = local.expected_subject
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Least-privilege: only Secrets Manager entries named vault-<tenant_id>-* in this
# account and region.
resource "aws_iam_role_policy" "secrets_sync" {
  name = "${local.name_prefix}-policy"
  role = aws_iam_role.secrets_sync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_resource_prefix}*"
      }
    ]
  })
}

# Let the new IAM OIDC provider and role propagate before the destination's first
# STS call on a fresh apply.
resource "time_sleep" "wait_for_iam" {
  create_duration = "30s"

  depends_on = [
    aws_iam_openid_connect_provider.vault_secrets_sync,
    aws_iam_role.secrets_sync,
    aws_iam_role_policy.secrets_sync,
  ]
}
