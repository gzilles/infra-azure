resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "PerGB2018"
  retention_in_days = var.retention_in_days
  daily_quota_gb    = var.daily_quota_gb

  tags = var.tags
}

# Workspace-based: a telemetria vai para o Log Analytics acima e herda a cota
# diária e a retenção dele.
resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  workspace_id     = azurerm_log_analytics_workspace.this.id
  application_type = "web"

  tags = var.tags
}
