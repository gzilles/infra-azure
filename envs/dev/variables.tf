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

variable "cosmos_ip_range_filter" {
  description = "IPs públicos liberados no firewall do Cosmos. Deve ficar vazio; só recebe o IP do operador temporariamente para o seed."
  type        = set(string)
  default     = []
}

variable "function_maximum_instance_count" {
  description = "Teto de instâncias da Function. Só limita o scale-out: no Flex não há custo por instância parada."
  type        = number
  default     = 1
}

variable "function_instance_memory_mb" {
  description = "Memória por instância da Function (512, 2048 ou 4096). A de 512 MB tem só 0,25 núcleo."
  type        = number
  default     = 512
}

variable "function_http_concurrency" {
  description = "Requisições HTTP simultâneas por instância da Function. null = padrão da plataforma (1 em Python)."
  type        = number
  default     = null
}

variable "api_auth_mode" {
  description = "Modo de autenticação da API (app setting AUTH_MODE). Veja modules/function_app."
  type        = string
  default     = "entra"
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
