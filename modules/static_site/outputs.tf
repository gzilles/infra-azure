output "id" {
  description = "ID da storage account do site."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Nome da storage account do site (destino do upload, container $web)."
  value       = azurerm_storage_account.this.name
}

output "default_host_name" {
  description = "Hostname público do site, ex.: <conta>.z15.web.core.windows.net."
  value       = azurerm_storage_account.this.primary_web_host
}

output "url" {
  description = "URL pública do site."
  value       = azurerm_storage_account.this.primary_web_endpoint
}
