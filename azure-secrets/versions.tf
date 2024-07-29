terraform {
  required_version = ">=1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.111"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.3"
    }
  }
}

