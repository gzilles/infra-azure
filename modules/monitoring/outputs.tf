output "workspace_id" {
  description = "ID do workspace do Log Analytics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "app_insights_id" {
  description = "ID do Application Insights."
  value       = azurerm_application_insights.this.id
}

output "app_insights_connection_string" {
  description = "Connection string do Application Insights, para o app setting da Function."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
