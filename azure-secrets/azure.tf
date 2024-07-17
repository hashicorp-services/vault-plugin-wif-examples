provider "azurerm" {
  features {}
}

provider "azuread" {
}

data "azuread_client_config" "current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  display_name = "Microsoft Graph"
}

resource "azuread_application" "vault_plugin_wif_application" {
  display_name = "vault-plugin-wif-application"
  # owners       = [data.azuread_client_config.current.object_id]

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
  # owners         = [data.azuread_client_config.current.object_id]
}

resource "azurerm_role_assignment" "user_access_administrator" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.vault_plugin_wif_service_principal.object_id
}

resource "azuread_application_federated_identity_credential" "vault_plugin_wif_federated_credential" {
  application_id = azuread_application.vault_plugin_wif_application.id
  display_name   = "vault-plugin-wif-federated-credential"
  audiences      = [var.azure_audience]
  issuer         = "${var.public_oidc_issuer_url}/v1/identity/oidc/plugins"
  subject        = "plugin-identity:root:secret:${data.vault_generic_secret.azure_secret_mount_details.data.accessor}"
}


