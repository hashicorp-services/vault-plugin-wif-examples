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
  allowed_client_ids = [var.azure_audience]
}

data "vault_generic_secret" "azure_secret_mount_details" {
  path    = "sys/mounts/${vault_azure_secret_backend.azure.path}"
  version = 1
}

resource "vault_azure_secret_backend" "azure" {
  path                    = "azure"
  subscription_id         = data.azurerm_subscription.current.subscription_id
  tenant_id               = data.azurerm_subscription.current.tenant_id
  client_id               = azuread_application.vault_plugin_wif_application.client_id
  identity_token_audience = var.azure_audience
  identity_token_ttl      = 60 * 5 # 5 minutes
  identity_token_key      = vault_identity_oidc_key.plugin_wif.id
}

resource "vault_azure_secret_backend_role" "test" {
  backend = vault_azure_secret_backend.azure.path
  role    = "test"
  ttl     = 600
  max_ttl = 900
  # sign_in_audience = var.azure_audience
  # application_object_id = var.azure_data_plane_access_object_id

  azure_roles {
    role_name = "Reader"
    scope     = azurerm_resource_group.example.id
  }
}

resource "azurerm_resource_group" "example" {
  name     = var.app_prefix
  location = "UK West"
}
