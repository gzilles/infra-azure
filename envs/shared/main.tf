# Raiz para o que é da subscription inteira, não de um ambiente. O workspace
# é só lido: quem o cria e o gerencia é a raiz do ambiente dono (hoje, o dev).
data "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.log_analytics_workspace_resource_group
}

# Plano de controle da subscription: RBAC, firewall, chaves, deploys, policy.
# Vai para a tabela AzureActivity, que registra o que acontece em dev, stg e prd.
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id

  dynamic "enabled_log" {
    for_each = toset(var.activity_log_categories)

    content {
      category = enabled_log.value
    }
  }
}
