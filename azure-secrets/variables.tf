variable "public_oidc_issuer_url" {
  type        = string
  description = "Publicly available URL of Vault or an external proxy that serves the OIDC discovery document."

  validation {
    condition     = startswith(var.public_oidc_issuer_url, "https://")
    error_message = "The 'public_oidc_issuer_url' must start with https://, e.g. 'https://vault.foo.com'."
  }
}

variable "azure_audience" {
  type        = string
  default     = "api://AzureADTokenExchange"
  description = "List of audiences (aud) that identify the intended recipients of the token."
}

variable "application_permissions" {
  type        = list(string)
  description = "The list of MS Graph API permissions must be assigned to the service principal provided to Vault for managing Azure. "
  default = [
    "GroupMember.ReadWrite.All",

    # Dynamic Service Principals
    "Application.ReadWrite.OwnedBy",

    # Existing Service Principals
    "Application.ReadWrite.All",
  ]
}
