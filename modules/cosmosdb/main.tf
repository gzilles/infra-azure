resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmos-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  offer_type = "Standard"
  kind       = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # Sem chaves: todo acesso a dados passa por Entra ID + RBAC de plano de dados.
  local_authentication_enabled = false

  # Firewall fechado: só as subnets listadas e, temporariamente, IPs explícitos.
  public_network_access_enabled     = true
  is_virtual_network_filter_enabled = true
  ip_range_filter                   = var.ip_range_filter

  dynamic "virtual_network_rule" {
    for_each = toset(var.allowed_subnet_ids)

    content {
      id = virtual_network_rule.value
    }
  }

  tags = var.tags
}

# Requisições de dados (403 de firewall/RBAC, principal inesperado) e de
# controle (mudanças de configuração). "Dedicated" grava nas tabelas CDB*.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                           = "diag-log-analytics"
  target_resource_id             = azurerm_cosmosdb_account.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "ControlPlaneRequests"
  }
}

resource "azurerm_cosmosdb_sql_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}

resource "azurerm_cosmosdb_sql_container" "this" {
  name                = var.container_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  database_name       = azurerm_cosmosdb_sql_database.this.name
  partition_key_paths = [var.partition_key_path]
}
