output "id" {
  description = "ID da conta do Cosmos DB."
  value       = azurerm_cosmosdb_account.this.id
}

output "name" {
  description = "Nome da conta do Cosmos DB."
  value       = azurerm_cosmosdb_account.this.name
}

output "endpoint" {
  description = "Endpoint do Cosmos DB (não é segredo; o acesso exige Entra ID)."
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "database_name" {
  description = "Nome do database SQL."
  value       = azurerm_cosmosdb_sql_database.this.name
}

output "container_name" {
  description = "Nome do container SQL."
  value       = azurerm_cosmosdb_sql_container.this.name
}
