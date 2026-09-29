locals {
  name_prefix         = "${var.application}-${var.environment}-${var.location_short}"
  resource_group_name = "rg-${local.name_prefix}"

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

# O resource group é criado pelo bootstrap (bootstrap/bootstrap.sh), não pelo
# Terraform: cada identidade de CI só tem Contributor dentro do seu próprio RG,
# então dev não teria permissão de criar o RG de prd mesmo que tentasse — e o
# Terraform, por só ler o RG, nunca tem como destruí-lo.
data "azurerm_resource_group" "main" {
  name = local.resource_group_name
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  address_space       = var.address_space
  subnets             = var.subnets
  tags                = local.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix         = local.name_prefix
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  tags                = local.tags
}

module "storage" {
  source = "../../modules/storage"

  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  replication_type    = var.storage_replication_type
  containers          = ["app-data", "func-deploy"]

  # Só as subnets de dados e da aplicação (Function) alcançam a conta.
  allowed_subnet_ids = [
    module.networking.subnet_ids["data"],
    module.networking.subnet_ids["app"],
  ]

  tags = local.tags
}
