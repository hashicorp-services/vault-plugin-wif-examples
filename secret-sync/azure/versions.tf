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
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned to 3.x; provider 4.x requires explicit subscription_id — reviewed migration needed.
      version = "~> 3.111"
    }
    azuread = {
      source = "hashicorp/azuread"
      # Pinned to 2.x; provider 3.x changes the federated credential schema — reviewed migration needed.
      version = "~> 2.53"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      # Unique suffix for the global Key Vault name (Azure soft-deletes vaults 90d).
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
