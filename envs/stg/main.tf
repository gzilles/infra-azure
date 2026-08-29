locals {
  name_prefix = "${var.application}-${var.environment}-${var.location_short}"

  tags = merge(var.tags, {
    environment = var.environment
    application = var.application
    managed_by  = "terraform"
    repository  = "infra-azure"
  })

  # Storage accounts não aceitam hífen e têm limite de 24 caracteres.
  storage_account_name = substr(
    replace(lower("st${var.application}${var.environment}${random_string.storage_suffix.result}"), "/[^a-z0-9]/", ""),
    0,
    24
  )
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false

  # Mudar qualquer keeper recria a conta — trate como identidade, não como detalhe.
  keepers = {
    application = var.application
    environment = var.environment
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.address_space
  subnets             = var.subnets
  tags                = local.tags
}

module "storage" {
  source = "../../modules/storage"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  replication_type    = var.storage_replication_type
  containers          = ["app-data"]

  # Só a subnet de dados alcança a conta; o resto é negado.
  allowed_subnet_ids = [module.networking.subnet_ids["data"]]

  tags = local.tags
}
