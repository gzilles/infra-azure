output "id" {
  description = "ID da storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Nome da storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Endpoint primário de blob."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "principal_id" {
  description = "Object ID da managed identity da conta, para conceder RBAC em outros recursos."
  value       = azurerm_storage_account.this.identity[0].principal_id
}

output "container_names" {
  description = "Containers criados pelo módulo."
  value       = [for c in azurerm_storage_container.this : c.name]
}
