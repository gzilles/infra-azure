variable "name" {
  description = "Nome da storage account. Globalmente único, 3-24 caracteres, apenas minúsculas e dígitos."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Nome inválido: use 3-24 caracteres, somente letras minúsculas e dígitos."
  }
}

variable "resource_group_name" {
  description = "Resource group onde a storage account será criada."
  type        = string
}

variable "location" {
  description = "Região da Azure."
  type        = string
}

variable "account_tier" {
  description = "Tier da conta: Standard ou Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier deve ser 'Standard' ou 'Premium'."
  }
}

variable "replication_type" {
  description = "Replicação: LRS, ZRS, GRS, RAGRS, GZRS ou RAGZRS."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type inválido."
  }
}

variable "retention_days" {
  description = "Dias de soft delete para blobs e containers."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 365
    error_message = "retention_days deve estar entre 1 e 365."
  }
}

variable "shared_access_key_enabled" {
  description = "Permitir autenticação por chave compartilhada. Mantenha false e use Entra ID (RBAC)."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Expor a conta na internet pública. Em produção, prefira false + Private Endpoint."
  type        = bool
  default     = true
}

variable "network_rules_default_action" {
  description = "Ação padrão do firewall: 'Deny' (recomendado) ou 'Allow'."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules_default_action)
    error_message = "Use 'Allow' ou 'Deny'."
  }
}

variable "allowed_subnet_ids" {
  description = "Subnets autorizadas no firewall da conta (exigem service endpoint Microsoft.Storage)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "IPs ou CIDRs públicos autorizados no firewall da conta."
  type        = list(string)
  default     = []
}

variable "containers" {
  description = "Containers de blob a criar. Todos são privados."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Workspace do Log Analytics que recebe os logs de escrita e exclusão de blobs. null = nenhum diagnostic setting."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo."
  type        = map(string)
  default     = {}
}
