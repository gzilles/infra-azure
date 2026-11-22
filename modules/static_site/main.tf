# Conta dedicada ao site: o endpoint web obedece ao firewall da conta, então
# ele precisa ficar aberto. Por isso esta conta guarda só arquivos públicos
# (HTML/CSS/JS) e nunca dados da aplicação, que ficam na conta fechada.
resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  # Sem bloco network_rules: o padrão da Azure já é "Allow". Declarar
  # default_action = "Allow" sem regras gera diff perpétuo, porque a API não
  # devolve o bloco nesse caso.
  public_network_access_enabled = true

  tags = var.tags
}

# Escrita e exclusão detectam alteração do site ($web); leitura mostra o
# acesso e tentativas com chave compartilhada também nos GETs.
resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  # Sem log_analytics_destination_type: StorageBlobLogs já é a tabela própria
  # do recurso, e a Azure não devolve o campo, o que gera diff perpétuo.
  name                       = "diag-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_storage_account_static_website" "this" {
  storage_account_id = azurerm_storage_account.this.id
  index_document     = var.index_document
  error_404_document = var.error_404_document
}
