terraform {
  # Write-only arguments (identity_token_*_wo) require Terraform 1.11 or later.
  required_version = ">= 1.11.0"

  required_providers {
    vault = {
      source = "hashicorp/vault"
      # vault_activation_flags + WIF write-only fields require Vault 2.0.0+.
      # Pin to 6.x to avoid an unreviewed major upgrade.
      version = "~> 6.0"
    }
    google = {
      source = "hashicorp/google"
      # Pinned to 5.x; provider 6.x exists and needs a reviewed migration.
      version = "~> 5.36"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      # Unique suffix for IDs reused across apply/destroy (GCP soft-deletes pools 30d).
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
