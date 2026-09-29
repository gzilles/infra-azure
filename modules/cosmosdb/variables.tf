variable "name_prefix" {
  description = "Prefixo de nomenclatura, ex.: 'meuapp-dev-brs'. Compõe o nome cosmos-<prefixo>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix deve ter 3-30 caracteres minúsculos, dígitos ou hífen, começando e terminando com alfanumérico."
  }
}

variable "resource_group_name" {
  description = "Resource group onde a conta do Cosmos DB será criada."
  type        = string
}

variable "location" {
  description = "Região da Azure (única região de escrita da conta)."
  type        = string
}

variable "allowed_subnet_ids" {
  description = "Subnets autorizadas no firewall da conta (exigem service endpoint Microsoft.AzureCosmosDB)."
  type        = list(string)
  default     = []
}

variable "ip_range_filter" {
  description = "IPs ou CIDRs públicos autorizados no firewall. Mantenha vazio; use só temporariamente (ex.: seed a partir da máquina do operador)."
  type        = set(string)
  default     = []
}

variable "database_name" {
  description = "Nome do database SQL."
  type        = string
}

variable "container_name" {
  description = "Nome do container SQL."
  type        = string
}

variable "partition_key_path" {
  description = "Partition key do container, ex.: '/organizationId'."
  type        = string

  validation {
    condition     = startswith(var.partition_key_path, "/")
    error_message = "partition_key_path deve começar com '/'."
  }
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo."
  type        = map(string)
  default     = {}
}
