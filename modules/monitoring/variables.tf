variable "name_prefix" {
  description = "Prefixo de nomenclatura, ex.: 'meuapp-dev-brs'. Compõe os nomes log-<prefixo> e appi-<prefixo>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix deve ter 3-30 caracteres minúsculos, dígitos ou hífen, começando e terminando com alfanumérico."
  }
}

variable "resource_group_name" {
  description = "Resource group onde os recursos de observabilidade serão criados."
  type        = string
}

variable "location" {
  description = "Região da Azure."
  type        = string
}

variable "daily_quota_gb" {
  description = "Limite diário de ingestão do Log Analytics, em GB. Ao atingir, a ingestão para até o dia seguinte. -1 = sem limite."
  type        = number
  default     = 0.1

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb > 0
    error_message = "daily_quota_gb deve ser maior que zero, ou -1 para sem limite."
  }
}

variable "retention_in_days" {
  description = "Retenção dos logs em dias. 30 é o mínimo e está incluído no preço de ingestão."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days deve estar entre 30 e 730."
  }
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
