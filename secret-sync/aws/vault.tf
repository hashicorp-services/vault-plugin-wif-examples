provider "vault" {
  # Connection configured via env: VAULT_ADDR, VAULT_TOKEN, VAULT_SKIP_VERIFY.
}

# Public OIDC issuer URL so AWS can fetch the discovery doc + JWKS to verify tokens.
resource "vault_identity_oidc" "issuer" {
  issuer = var.public_oidc_issuer_url
}

# Signing key for the WIF identity tokens; the audience must be in allowed_client_ids.
resource "vault_identity_oidc_key" "secrets_sync" {
  name               = "${local.name_prefix}-key"
  algorithm          = "RS256"
  rotation_period    = 60 * 60 * 24 # 24 hours
  verification_ttl   = 60 * 60 * 24 # 24 hours
  allowed_client_ids = [local.aws_audience]
}

# Publishes the signing key to the issuer's JWKS. Vault only advertises a key
# there when it is referenced by an OIDC role or mount; a sync destination is
# neither, so without this role the JWKS is empty and the WIF exchange fails.
resource "vault_identity_oidc_role" "publish_key" {
  name = "${local.name_prefix}-key-publisher"
  key  = vault_identity_oidc_key.secrets_sync.name
}

# One-time secrets sync activation; cannot be undone, so destroy only drops it from state.
resource "vault_activation_flags" "secrets_sync" {
  feature = "secrets-sync"
}

# WIF sync destination (no static credentials). Audience and key are write-only
# (not stored in state); bump the matching *_wo_version to roll a new value.
resource "vault_secrets_sync_aws_destination" "this" {
  name     = local.destination_name
  region   = var.aws_region
  role_arn = aws_iam_role.secrets_sync.arn

  identity_token_audience_wo         = local.aws_audience
  identity_token_audience_wo_version = 1
  identity_token_key_wo              = vault_identity_oidc_key.secrets_sync.name
  identity_token_key_wo_version      = 1
  identity_token_ttl                 = 60 * 60 # 1 hour

  granularity          = "secret-path"
  secret_name_template = local.secret_name_template

  custom_tags = local.common_tags

  depends_on = [
    vault_activation_flags.secrets_sync,
    vault_identity_oidc_role.publish_key,
    time_sleep.wait_for_iam,
  ]
}

# The tenant's KV v2 mount and a demo secret to synchronize.
resource "vault_mount" "kv" {
  path = local.kv_mount_path
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "demo" {
  mount = vault_mount.kv.path
  name  = var.secret_name

  data_json = jsonencode({
    foo = "bar"
  })
}

# Associating the secret triggers the first sync; updates/deletes propagate automatically.
resource "vault_secrets_sync_association" "demo" {
  name        = vault_secrets_sync_aws_destination.this.name
  type        = vault_secrets_sync_aws_destination.this.type
  mount       = vault_mount.kv.path
  secret_name = vault_kv_secret_v2.demo.name
}
