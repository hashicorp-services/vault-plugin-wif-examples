provider "azurerm" {
  # azurerm v4+ requires an explicit subscription; null falls back to ARM_SUBSCRIPTION_ID.
  subscription_id = var.azure_subscription_id

  # Don't auto-register resource providers: the example uses already-registered RPs
  # (e.g. Microsoft.KeyVault), and the v4 default ("core") needs elevated perms and
  # stalls provider startup on some subscriptions.
  resource_provider_registrations = "none"

  features {
    key_vault {
      # The random_string suffix already gives each apply a unique vault name, so
      # skip the slow (~10 min) synchronous purge: destroy only soft-deletes (fast)
      # and Azure expires the vault after 90 days. recover covers fixed-name reuse.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}

# Entra tenant + subscription of the active Azure login.
data "azurerm_client_config" "current" {}

data "vault_namespace" "current" {}

locals {
  # Secrets sync uses a dedicated issuer path (identity/oidc/secrets-sync).
  oidc_base_url = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer.issuer}/v1/identity/oidc/secrets-sync" : "${vault_identity_oidc.issuer.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/secrets-sync"

  # Per-tenant resource names, all derived from var.tenant_id.
  name_prefix          = "${var.tenant_id}-secrets-sync"                # app registration, OIDC key/role, FIC
  destination_name     = "${var.tenant_id}-azure-kv"                    # Vault sync destination (drives the token sub)
  kv_mount_path        = "${var.tenant_id}-kv"                          # the tenant's KV v2 mount
  secret_name_template = "vault-${var.tenant_id}-{{ .SecretBaseName }}" # synced secret name in Azure Key Vault

  # Template with {{ .SecretBaseName }} resolved to var.secret_name.
  expected_azure_secret_name = replace(local.secret_name_template, "{{ .SecretBaseName }}", var.secret_name)

  # Token sub: secrets-sync:<namespace>:<type>:<name> (root ns => "root"); pinned
  # by the federated identity credential.
  namespace_segment = data.vault_namespace.current.id == "/" ? "root" : data.vault_namespace.current.id
  expected_subject  = "secrets-sync:${local.namespace_segment}:azure-kv:${local.destination_name}"

  # Tags applied to every taggable resource.
  common_tags = {
    "managed-by" = "terraform-vault-secrets-sync"
    "tenant"     = var.tenant_id
  }
}

# Unique suffix for the global Key Vault name (Azure soft-deletes vaults 90d).
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# App registration for the sync workload; its client ID is used by the destination
# and trusted by the federated credential.
resource "azuread_application" "secrets_sync" {
  display_name = "${local.name_prefix}-app"
}

# Service principal for the app; Key Vault RBAC is granted to its object ID.
resource "azuread_service_principal" "secrets_sync" {
  client_id = azuread_application.secrets_sync.client_id
}

# Federated identity credential trusting Vault's issuer; subject pins the exact
# token sub so only this destination can federate in.
resource "azuread_application_federated_identity_credential" "secrets_sync" {
  application_id = azuread_application.secrets_sync.id
  display_name   = "${local.name_prefix}-fic"
  audiences      = [var.azure_audience]
  issuer         = local.oidc_base_url
  subject        = local.expected_subject
}

# Resource group that holds the Key Vault.
resource "azurerm_resource_group" "secrets_sync" {
  name     = "${local.name_prefix}-rg"
  location = var.azure_location

  tags = local.common_tags
}

# Key Vault receiving the synced secret. RBAC authorization (not access policies)
# so the SP gets data-plane access via a role assignment.
resource "azurerm_key_vault" "secrets_sync" {
  name                       = "kv-${var.tenant_id}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.secrets_sync.name
  location                   = azurerm_resource_group.secrets_sync.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true

  tags = local.common_tags
}

# Least-privilege data-plane access: the SP may manage secrets in this vault only.
resource "azurerm_role_assignment" "secrets_sync" {
  scope                = azurerm_key_vault.secrets_sync.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.secrets_sync.object_id
}

# Let the new app/SP/FIC and role assignment propagate before the destination's
# first token exchange and write. Entra propagation is slow; 60s is the cap,
# re-run a flaky fresh apply rather than raising it.
resource "time_sleep" "wait_for_iam" {
  create_duration = "60s"

  depends_on = [
    azuread_application_federated_identity_credential.secrets_sync,
    azuread_service_principal.secrets_sync,
    azurerm_role_assignment.secrets_sync,
  ]
}
