terraform {
  # Write-only arguments (identity_token_*_wo) require Terraform 1.11 or later.
  required_version = ">= 1.11.0"

  required_providers {
    vault = {
      source = "hashicorp/vault"
      # Requires Vault Enterprise 2.0.0+ (WIF *_wo fields) and provider 5.10+ (vault_activation_flags).
      version = "~> 5.10"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
