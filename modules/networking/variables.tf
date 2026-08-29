variable "name_prefix" {
  description = "Prefixo de nomenclatura, ex.: 'meuapp-dev-brs'. Compõe o nome da VNet e das subnets."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix deve ter 3-30 caracteres minúsculos, dígitos ou hífen, começando e terminando com alfanumérico."
  }
}

variable "resource_group_name" {
  description = "Resource group onde a rede será criada."
  type        = string
}

variable "location" {
  description = "Região da Azure, ex.: 'brazilsouth'."
  type        = string
}

variable "address_space" {
  description = "Blocos CIDR da virtual network."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0
    error_message = "Informe ao menos um bloco CIDR."
  }
}

variable "subnets" {
  description = <<-EOT
    Mapa de subnets. A chave vira parte do nome (snet-<chave>-<name_prefix>).
    Cada subnet ganha um NSG dedicado, já associado.

    Exemplo:
      subnets = {
        app  = { address_prefixes = ["10.10.1.0/24"] }
        data = { address_prefixes = ["10.10.2.0/24"], service_endpoints = ["Microsoft.Storage"] }
      }
  EOT

  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(object({
      name    = string
      actions = optional(list(string), [])
    }))
  }))

  default = {}
}

variable "dns_servers" {
  description = "DNS servers customizados da VNet. Vazio = DNS padrão da Azure."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
