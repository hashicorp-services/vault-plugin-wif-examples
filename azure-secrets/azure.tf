provider "azurerm" {
  features {}
}

provider "azuread" {
}

locals {
  oidc_base_url = data.vault_namespace.current.id == "/" ? "${vault_identity_oidc.issuer_url.issuer}/v1/identity/oidc/plugins" : "${vault_identity_oidc.issuer_url.issuer}/v1/${data.vault_namespace.current.id}identity/oidc/plugins"
}

data "vault_namespace" "current" {}

data "azuread_client_config" "current" {}

data "azurerm_subscription" "current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  display_name = "Microsoft Graph"
}

resource "azuread_application" "vault_plugin_wif_application" {
  display_name = "${var.app_prefix}-application"

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

    dynamic "resource_access" {
      for_each = toset(var.application_permissions)

      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "vault_plugin_wif_service_principal" {
  client_id = azuread_application.vault_plugin_wif_application.client_id
}

resource "azurerm_role_assignment" "user_access_administrator" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.vault_plugin_wif_service_principal.object_id
}

resource "azuread_application_federated_identity_credential" "vault_plugin_wif_federated_credential" {
  application_id = azuread_application.vault_plugin_wif_application.id
  display_name   = "${var.app_prefix}-federated-credential"
  audiences      = [var.azure_audience]
  issuer         = local.oidc_base_url
  subject        = "plugin-identity:${var.vault_namespace_id}:secret:${data.vault_generic_secret.azure_secret_mount_details.data.accessor}"
}


