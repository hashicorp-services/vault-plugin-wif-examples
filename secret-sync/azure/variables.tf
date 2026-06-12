variable "public_oidc_issuer_url" {
  type        = string
  description = "Publicly reachable base URL of Vault (or a proxy/gateway in front of it) that Azure can use to fetch the secrets sync OIDC discovery document and public keys to validate identity tokens. For example 'https://vault.example.com'."
  nullable    = false

  validation {
    condition     = startswith(var.public_oidc_issuer_url, "https://")
    error_message = "The 'public_oidc_issuer_url' must start with https://, e.g. 'https://vault.example.com'."
  }
}

variable "tenant_id" {
  type        = string
  description = "Tenant or application identifier (NOT the Azure Entra tenant; that is read from the active Azure login). Every Vault and Azure resource name in this example is derived from it: KV mount '<tenant_id>-kv', sync destination '<tenant_id>-azure-kv', app/OIDC prefix '<tenant_id>-secrets-sync', Key Vault 'kv-<tenant_id>-<random>', and synced secret name 'vault-<tenant_id>-<secret_name>'. This gives each tenant an isolated, self-describing footprint."
  default     = "app1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9]*(-[a-z0-9]+)*)?$", var.tenant_id))
    error_message = "The 'tenant_id' must start with a lowercase letter and contain only lowercase letters, digits, and non-consecutive hyphens (no leading or trailing hyphen), to satisfy the strictest cloud naming rules across the three examples."
  }

  validation {
    condition     = length(var.tenant_id) <= 14
    error_message = "The 'tenant_id' must be 14 characters or fewer: it is embedded in the globally-unique Azure Key Vault name 'kv-<tenant_id>-<6 random chars>', which is limited to 24 characters."
  }
}

variable "azure_location" {
  type        = string
  description = "Azure region where the resource group and Key Vault are created."
  default     = "eastus"
  nullable    = false
}

variable "azure_audience" {
  type        = string
  description = "Audience (aud) claim of the WIF identity token. Azure's federated identity credentials expect 'api://AzureADTokenExchange' by default; the same value is pinned by the OIDC key's allowed_client_ids and the federated identity credential's audiences."
  default     = "api://AzureADTokenExchange"
  nullable    = false
}

variable "secret_name" {
  type        = string
  description = "Name of the demo KV v2 secret, created inside the tenant's mount, to synchronize to Azure Key Vault."
  default     = "my-secret"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", "vault-${var.tenant_id}-${var.secret_name}"))
    error_message = "The rendered Azure Key Vault secret name 'vault-<tenant_id>-<secret_name>' must contain only letters, digits, and hyphens (Azure Key Vault secret names disallow underscores)."
  }
}
