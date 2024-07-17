variable "gcp_project_id" {
  type        = string
  description = "The ID for your GCP project"
}

variable "public_oidc_issuer_url" {
  type        = string
  description = "Publicly available URL of Vault or an external proxy that serves the OIDC discovery document."

  validation {
    condition     = startswith(var.public_oidc_issuer_url, "https://")
    error_message = "The 'public_oidc_issuer_url' must start with https://, e.g. 'https://vault.foo.com'."
  }
}

variable "activate_apis" {
  description = "The list of apis to activate within the project"
  type        = list(string)
  default = [
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com"
  ]
}

variable "vault_gcp_secret_permissions" {
  type        = list(string)
  description = "The list of permissions for Vault GCP auth custom IAM role."
  default = [
    # Service account + key admin
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.update",
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",

    # For `access_token` secrets and impersonated accounts
    "iam.serviceAccounts.getAccessToken",

    # For `service_account_keys` secrets
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",

    # When using rolesets or static accounts with bindings, Vault must have permissions on those resources.
    # Projects
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",

    # # All compute
    # "compute.*.getIamPolicy",
    # "compute.*.setIamPolicy",

  ]
}
