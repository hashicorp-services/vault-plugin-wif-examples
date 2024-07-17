terraform {
  required_version = ">=1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.57"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.3"
    }
  }
}
