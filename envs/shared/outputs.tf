output "activity_log_diagnostic_setting_id" {
  description = "ID do diagnostic setting que exporta o Activity Log."
  value       = azurerm_monitor_diagnostic_setting.activity_log.id
}

output "log_analytics_workspace_id" {
  description = "Workspace que recebe o Activity Log."
  value       = data.azurerm_log_analytics_workspace.main.id
}
