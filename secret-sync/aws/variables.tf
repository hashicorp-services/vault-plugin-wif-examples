variable "public_oidc_issuer_url" {
  type        = string
  description = "Publicly reachable base URL of Vault (or a proxy/gateway in front of it) that AWS can use to fetch the secrets sync OIDC discovery document and public keys. For example 'https://vault.example.com'."
  nullable    = false

  validation {
    condition     = startswith(var.public_oidc_issuer_url, "https://")
    error_message = "The 'public_oidc_issuer_url' must start with https://, e.g. 'https://vault.example.com'."
  }
}

variable "tenant_id" {
  type        = string
  description = "Tenant or application identifier. Every Vault and AWS resource name in this example is derived from it: KV mount '<tenant_id>-kv', sync destination '<tenant_id>-aws-sm', IAM/OIDC prefix '<tenant_id>-secrets-sync', and synced secret prefix 'vault-<tenant_id>-'. This gives each tenant an isolated, self-describing footprint."
  default     = "app1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9]*(-[a-z0-9]+)*)?$", var.tenant_id))
    error_message = "The 'tenant_id' must start with a lowercase letter and contain only lowercase letters, digits, and non-consecutive hyphens (no leading or trailing hyphen), to satisfy the strictest cloud naming rules across the three examples."
  }

  validation {
    condition     = length(var.tenant_id) <= 46
    error_message = "The 'tenant_id' must be 46 characters or fewer: it is embedded in the IAM role name '<tenant_id>-secrets-sync-role', which is limited to 64 characters."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region where synced secrets are managed in AWS Secrets Manager."
  default     = "us-east-1"
  nullable    = false
}

variable "aws_audience" {
  type        = string
  description = "Audience (aud) claim of the WIF identity token. Leave empty to derive it from the issuer URL without its scheme: '<host>/v1/identity/oidc/secrets-sync'."
  default     = ""
  nullable    = false
}

variable "secret_name" {
  type        = string
  description = "Name of the demo KV v2 secret, created inside the tenant's mount, to synchronize to AWS Secrets Manager."
  default     = "my-secret"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]+$", "vault-${var.tenant_id}-${var.secret_name}"))
    error_message = "The rendered AWS Secrets Manager secret name 'vault-<tenant_id>-<secret_name>' must contain only letters, digits, and the characters / _ + = . @ -."
  }
}
