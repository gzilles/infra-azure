output "saved_search_ids" {
  description = "Mapa nome => ID das consultas salvas."
  value       = { for k, s in azurerm_log_analytics_saved_search.this : k => s.id }
}

output "category" {
  description = "Categoria em que as consultas aparecem no Log Analytics."
  value       = local.category
}
