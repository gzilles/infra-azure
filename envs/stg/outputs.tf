output "resource_group_name" {
  description = "Resource group principal do ambiente."
  value       = data.azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID da virtual network."
  value       = module.networking.vnet_id
}

output "subnet_ids" {
  description = "Mapa chave => ID das subnets."
  value       = module.networking.subnet_ids
}

output "storage_account_name" {
  description = "Nome da storage account da aplicação."
  value       = module.storage.name
}

output "storage_primary_blob_endpoint" {
  description = "Endpoint primário de blob."
  value       = module.storage.primary_blob_endpoint
}
