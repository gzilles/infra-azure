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

output "log_analytics_workspace_id" {
  description = "ID do workspace do Log Analytics."
  value       = module.monitoring.workspace_id
}

output "app_insights_id" {
  description = "ID do Application Insights."
  value       = module.monitoring.app_insights_id
}

output "cosmos_endpoint" {
  description = "Endpoint do Cosmos DB."
  value       = module.cosmosdb.endpoint
}

output "cosmos_database_name" {
  description = "Database SQL do Cosmos DB."
  value       = module.cosmosdb.database_name
}

output "cosmos_container_name" {
  description = "Container SQL do Cosmos DB."
  value       = module.cosmosdb.container_name
}

output "static_site_url" {
  description = "URL pública do front-end."
  value       = module.static_site.url
}

output "static_site_storage_account_name" {
  description = "Storage account do site (destino do upload no container $web)."
  value       = module.static_site.name
}

output "storage_account_name" {
  description = "Nome da storage account da aplicação."
  value       = module.storage.name
}

output "storage_primary_blob_endpoint" {
  description = "Endpoint primário de blob."
  value       = module.storage.primary_blob_endpoint
}
