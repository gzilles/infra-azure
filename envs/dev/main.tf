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

  static_site_storage_account_name = substr(
    replace(lower("stweb${var.application}${var.environment}${random_string.storage_suffix.result}"), "/[^a-z0-9]/", ""),
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

module "cosmosdb" {
  source = "../../modules/cosmosdb"

  name_prefix         = local.name_prefix
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  database_name       = "posture"
  container_name      = "posture"
  partition_key_path  = "/organizationId"

  # Só a subnet da aplicação (Function) alcança o Cosmos.
  allowed_subnet_ids = [module.networking.subnet_ids["app"]]
  ip_range_filter    = var.cosmos_ip_range_filter

  log_analytics_workspace_id = module.monitoring.workspace_id

  tags = local.tags
}

data "azurerm_client_config" "current" {}

# Operador (quem roda o terraform) com escrita no plano de dados, só para o seed.
# 00000000-0000-0000-0000-000000000002 = Cosmos DB Built-in Data Contributor.
resource "azurerm_cosmosdb_sql_role_assignment" "operator_data_contributor" {
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = module.cosmosdb.name
  role_definition_id  = "${module.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = data.azurerm_client_config.current.object_id
  scope               = module.cosmosdb.id
}

module "static_site" {
  source = "../../modules/static_site"

  name                = local.static_site_storage_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  log_analytics_workspace_id = module.monitoring.workspace_id

  tags = local.tags
}

# Operador publica o conteúdo do site ($web) com o próprio az login, sem chaves.
resource "azurerm_role_assignment" "operator_static_site_contributor" {
  scope                = module.static_site.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "function_app" {
  source = "../../modules/function_app"

  name_prefix         = local.name_prefix
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  subnet_id           = module.networking.subnet_ids["app"]

  deployment_container_endpoint = "${module.storage.primary_blob_endpoint}func-deploy"
  host_storage_account_name     = module.storage.name

  runtime_name           = "python"
  runtime_version        = "3.13"
  maximum_instance_count = var.function_maximum_instance_count
  instance_memory_in_mb  = var.function_instance_memory_mb
  http_concurrency       = var.function_http_concurrency

  app_settings = {
    COSMOS_ENDPOINT  = module.cosmosdb.endpoint
    COSMOS_DATABASE  = module.cosmosdb.database_name
    COSMOS_CONTAINER = module.cosmosdb.container_name
  }
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  auth_mode                      = var.api_auth_mode

  # Só o front-end pode chamar a API a partir do navegador.
  cors_allowed_origins = [trimsuffix(module.static_site.url, "/")]

  log_analytics_workspace_id = module.monitoring.workspace_id

  tags = local.tags
}

# Function lê o Cosmos pelo plano de dados.
# 00000000-0000-0000-0000-000000000001 = Cosmos DB Built-in Data Reader.
resource "azurerm_cosmosdb_sql_role_assignment" "function_data_reader" {
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = module.cosmosdb.name
  role_definition_id  = "${module.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = module.function_app.principal_id
  scope               = module.cosmosdb.id
}

# Host storage (leases e chaves das funções em blob) e container de deploy do
# Flex, ambos na conta de dados, acessados pela identidade da Function.
resource "azurerm_role_assignment" "function_storage_blob_owner" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = module.function_app.principal_id
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

  log_analytics_workspace_id = module.monitoring.workspace_id

  tags = local.tags
}
