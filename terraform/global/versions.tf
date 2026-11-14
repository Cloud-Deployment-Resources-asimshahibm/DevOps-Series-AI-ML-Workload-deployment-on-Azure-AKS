terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
  }
  # Local state on first apply; scripts/bootstrap-global.sh then writes backend.tf
  # and migrates this state into the storage account it just created.
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # shared keys are disabled on our storage accounts
}
