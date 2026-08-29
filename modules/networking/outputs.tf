output "vnet_id" {
  description = "ID da virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Nome da virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Mapa chave-da-subnet => ID da subnet."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "nsg_ids" {
  description = "Mapa chave-da-subnet => ID do NSG associado."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}
