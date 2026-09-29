resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type  = "Linux"
  sku_name = "FC1"

  tags = var.tags
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = "func-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  runtime_name           = var.runtime_name
  runtime_version        = var.runtime_version
  instance_memory_in_mb  = var.instance_memory_in_mb
  maximum_instance_count = var.maximum_instance_count

  # Pacote de deploy lido com a identidade da Function, sem chave de conta.
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = var.deployment_container_endpoint
  storage_authentication_type = "SystemAssignedIdentity"

  virtual_network_subnet_id = var.subnet_id

  https_only                                     = true
  public_network_access_enabled                  = true
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  # Host storage por identidade: só o nome da conta, nenhuma connection string.
  # O provider (até a 4.x) injeta AzureWebJobsStorage e
  # DEPLOYMENT_STORAGE_CONNECTION_STRING com a chave da conta; declarar os dois
  # vazios impede isso. O host cai no __accountName e o deploy já usa a identidade.
  app_settings = merge(var.app_settings, {
    AzureWebJobsStorage                  = ""
    AzureWebJobsStorage__accountName     = var.host_storage_account_name
    DEPLOYMENT_STORAGE_CONNECTION_STRING = ""
  })

  site_config {
    application_insights_connection_string = var.app_insights_connection_string
    minimum_tls_version                    = "1.2"

    # Todo o tráfego de saída passa pela subnet: é o que faz os service
    # endpoints valerem para o Cosmos e para a storage com firewall.
    vnet_route_all_enabled = true

    cors {
      allowed_origins = var.cors_allowed_origins
    }
  }

  tags = var.tags

  # A Azure acrescenta esta tag para ligar a Function ao App Insights no portal.
  lifecycle {
    ignore_changes = [tags["hidden-link: /app-insights-resource-id"]]
  }
}
