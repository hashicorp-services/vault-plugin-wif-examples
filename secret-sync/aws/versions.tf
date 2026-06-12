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
    aws = {
      source = "hashicorp/aws"
      # Pinned to 5.x; provider 6.x exists and needs a reviewed migration.
      version = "~> 5.57"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
