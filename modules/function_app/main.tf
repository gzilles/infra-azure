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
  http_concurrency       = var.http_concurrency

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
    AUTH_MODE                            = var.auth_mode
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

# O azurerm só expõe a política do WebDeploy (SCM) no recurso Flex. A do FTP
# é ajustada direto na API da Azure; o azapi mantém o valor no plan e detecta
# se alguém religar pelo portal.
resource "azapi_update_resource" "ftp_basic_auth" {
  count = var.ftp_publish_basic_authentication_enabled == null ? 0 : 1

  type      = "Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01"
  name      = "ftp"
  parent_id = azurerm_function_app_flex_consumption.this.id

  body = {
    properties = {
      allow = var.ftp_publish_basic_authentication_enabled
    }
  }
}

# Logs do host do Functions, para investigação (inicializações, erros de
# configuração, falhas de acesso a storage).
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  # Sem log_analytics_destination_type: FunctionAppLogs já é a tabela própria
  # do recurso, e a Azure não devolve o campo, o que gera diff perpétuo.
  name                       = "diag-log-analytics"
  target_resource_id         = azurerm_function_app_flex_consumption.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "FunctionAppLogs"
  }
}
