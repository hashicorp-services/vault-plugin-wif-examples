provider "google" {
  project = var.gcp_project_id
}

data "vault_namespace" "current" {}

locals {
  # Secrets sync uses a dedicated issuer path (identity/oidc/secrets-sync).
  oidc_base_url = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer.issuer}/v1/identity/oidc/secrets-sync" : "${vault_identity_oidc.issuer.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/secrets-sync"

  # Per-tenant resource names, all derived from var.tenant_id.
  name_prefix          = "${var.tenant_id}-secrets-sync"                # SA, OIDC key/role, and WIF pool/provider
  destination_name     = "${var.tenant_id}-gcp-sm"                      # Vault sync destination (drives the token sub)
  kv_mount_path        = "${var.tenant_id}-kv"                          # the tenant's KV v2 mount
  secret_name_template = "vault-${var.tenant_id}-{{ .SecretBaseName }}" # synced secret name in GCP Secret Manager

  # Template with {{ .SecretBaseName }} resolved to var.secret_name.
  expected_gcp_secret_name = replace(local.secret_name_template, "{{ .SecretBaseName }}", var.secret_name)

  # Literal provider ID; the audience is built from it (not the computed name) to
  # avoid a cycle between the audience, OIDC key, and pool provider.
  wif_provider_id = "${local.name_prefix}-provider"

  # WIF audience = the pool provider resource URL. Must match in the destination
  # audience, the OIDC key allowed_client_ids, and the provider allowed_audiences.
  gcp_audience = var.gcp_audience != "" ? var.gcp_audience : "https://iam.googleapis.com/${google_iam_workload_identity_pool.secrets_sync.name}/providers/${local.wif_provider_id}"

  # Token sub: secrets-sync:<namespace>:<type>:<name> (root ns => "root"). Pinned
  # by the provider attribute_condition and the SA impersonation binding.
  namespace_segment = data.vault_namespace.current.id == "/" ? "root" : data.vault_namespace.current.id
  expected_subject  = "secrets-sync:${local.namespace_segment}:gcp-sm:${local.destination_name}"

  # Labels applied to every labellable resource.
  common_tags = {
    "managed-by" = "terraform-vault-secrets-sync"
    "tenant"     = var.tenant_id
  }

  # Dedicated project for the pool/provider; falls back to the tenant project.
  wif_project     = var.wif_project_id != "" ? var.wif_project_id : var.gcp_project_id
  wif_is_separate = local.wif_project != var.gcp_project_id

  # Identity-side APIs the pool/provider project needs (only when it is separate;
  # otherwise activate_apis on the tenant project already covers them).
  wif_apis = [
    "iam.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

# Unique suffix for pool/SA IDs reused across apply/destroy (GCP soft-deletes pools 30d).
resource "random_id" "suffix" {
  byte_length = 2
}

# Enable the APIs the tenant resource project needs (all of var.activate_apis:
# Secret Manager, IAM, IAM Credentials, STS, and Cloud Resource Manager).
resource "google_project_service" "services" {
  for_each           = toset(var.activate_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

# Enable identity APIs in the dedicated WIF project (only when it is separate).
resource "google_project_service" "wif" {
  for_each           = local.wif_is_separate ? toset(local.wif_apis) : toset([])
  project            = local.wif_project
  service            = each.value
  disable_on_destroy = false
}

# Workload identity pool that trusts Vault's secrets sync OIDC issuer.
resource "google_iam_workload_identity_pool" "secrets_sync" {
  project                   = local.wif_project
  workload_identity_pool_id = "${local.name_prefix}-pool-${random_id.suffix.hex}"

  depends_on = [google_project_service.services, google_project_service.wif]
}

# Pool provider federating Vault tokens; attribute_condition pins the exact token
# sub so only this destination can federate in.
resource "google_iam_workload_identity_pool_provider" "secrets_sync" {
  project                            = local.wif_project
  workload_identity_pool_id          = google_iam_workload_identity_pool.secrets_sync.workload_identity_pool_id
  workload_identity_pool_provider_id = local.wif_provider_id

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  oidc {
    issuer_uri        = local.oidc_base_url
    allowed_audiences = [local.gcp_audience]
  }

  attribute_condition = "assertion.sub == \"${local.expected_subject}\""
}

# Service account Vault impersonates through workload identity federation.
resource "google_service_account" "secrets_sync" {
  project      = var.gcp_project_id
  account_id   = "${local.name_prefix}-sa-${random_id.suffix.hex}"
  display_name = "Vault secrets sync WIF service account (${var.tenant_id})"
}

# Allow the federated subject (this Vault destination) to impersonate the SA.
resource "google_service_account_iam_member" "wif" {
  service_account_id = google_service_account.secrets_sync.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.secrets_sync.name}/subject/${local.expected_subject}"
}

# Least-privilege role (the syncer's write scope) instead of roles/secretmanager.admin.
# The destination's project-level TestIamPermissions pre-flight checks these exact
# five permissions, so they must be granted at the project level.
resource "google_project_iam_custom_role" "secrets_sync" {
  # role_id allows only [A-Za-z0-9_.]; suffix avoids GCP's 7-day soft-delete on reuse.
  project     = var.gcp_project_id
  role_id     = "vaultSecretsSync_${replace(var.tenant_id, "-", "_")}_${random_id.suffix.hex}"
  title       = "Vault Secrets Sync Writer (${var.tenant_id})"
  description = "Least-privilege role for Vault secrets sync to write to GCP Secret Manager (syncer write scope)."

  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.update",
    "secretmanager.versions.add",
    "secretmanager.versions.destroy",
  ]
}

resource "google_project_iam_member" "secrets_sync" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.secrets_sync.id
  member  = google_service_account.secrets_sync.member
}

# Let the new WIF + IAM bindings propagate before the destination's first token
# exchange and write. 60s is the cap; re-run a flaky fresh apply rather than raising it.
resource "time_sleep" "wait_for_iam" {
  create_duration = "60s"

  depends_on = [
    google_iam_workload_identity_pool_provider.secrets_sync,
    google_service_account_iam_member.wif,
    google_project_iam_member.secrets_sync,
  ]
}
