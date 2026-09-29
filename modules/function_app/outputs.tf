output "id" {
  description = "ID da Function App."
  value       = azurerm_function_app_flex_consumption.this.id
}

output "name" {
  description = "Nome da Function App."
  value       = azurerm_function_app_flex_consumption.this.name
}

output "default_hostname" {
  description = "Hostname público da Function App."
  value       = azurerm_function_app_flex_consumption.this.default_hostname
}

output "principal_id" {
  description = "Object ID da identidade system-assigned, para conceder RBAC."
  value       = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}
