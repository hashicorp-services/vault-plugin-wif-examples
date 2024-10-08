variable "public_oidc_issuer_url" {
  type        = string
  description = "Publicly available URL of Vault or an external proxy that serves the OIDC discovery document."

  validation {
    condition     = startswith(var.public_oidc_issuer_url, "https://")
    error_message = "The 'public_oidc_issuer_url' must start with https://, e.g. 'https://vault.foo.com'."
  }
}

variable "aws_audience" {
  type        = string
  default     = "sts.amazonaws.com"
  description = "List of audiences (aud) that identify the intended recipients of the token."
}

variable "app_prefix" {
  type        = string
  description = "The prefix for the Vault plugin app"
  default     = "vault-plugin-wif"
}

variable "vault_namespace_id" {
  type        = string
  description = "Vault namespace ID, not the name or path."
  default     = "root"
}
