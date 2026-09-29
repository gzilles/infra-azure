variable "subscription_id" {
  description = "Subscription da Azure onde este ambiente vive."
  type        = string
}

variable "environment" {
  description = "Nome curto do ambiente: dev, stg ou prd."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment deve ser 'dev', 'stg' ou 'prd'."
  }
}

variable "application" {
  description = "Nome curto da aplicação/plataforma. Compõe a nomenclatura dos recursos."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.application))
    error_message = "application deve ter 2-12 caracteres minúsculos ou dígitos."
  }
}

variable "location" {
  description = "Região da Azure, ex.: 'brazilsouth'."
  type        = string
  default     = "brazilsouth"
}

variable "location_short" {
  description = "Abreviação da região usada na nomenclatura, ex.: 'brs'."
  type        = string
  default     = "brs"
}

variable "address_space" {
  description = "CIDR da virtual network do ambiente."
  type        = list(string)
}

variable "subnets" {
  description = "Subnets da VNet. Veja modules/networking para o formato."
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      name    = string
      actions = optional(list(string), [])
    }))
  }))
}

variable "storage_replication_type" {
  description = "Replicação da storage account da aplicação."
  type        = string
  default     = "LRS"
}

variable "log_analytics_daily_quota_gb" {
  description = "Limite diário de ingestão do Log Analytics, em GB. Protege o crédito: ao atingir, a telemetria para até o dia seguinte."
  type        = number
  default     = 0.1
}

variable "tags" {
  description = "Tags de negócio (centro de custo, dono, etc.). As tags técnicas são adicionadas automaticamente."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in ["cost_center", "owner"] : contains(keys(var.tags), k)])
    error_message = "As tags 'cost_center' e 'owner' são obrigatórias."
  }
}
