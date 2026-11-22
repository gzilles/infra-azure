terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
    # Só para o contato de segurança: a API que o azurerm usa aceita um e-mail só.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}
