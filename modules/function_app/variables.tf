variable "name_prefix" {
  description = "Prefixo de nomenclatura, ex.: 'meuapp-dev-brs'. Compõe os nomes func-<prefixo> e asp-<prefixo>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix deve ter 3-30 caracteres minúsculos, dígitos ou hífen, começando e terminando com alfanumérico."
  }
}

variable "resource_group_name" {
  description = "Resource group onde o plano e a Function serão criados."
  type        = string
}

variable "location" {
  description = "Região da Azure."
  type        = string
}

variable "subnet_id" {
  description = "Subnet da VNet integration. Precisa estar delegada a Microsoft.App/environments."
  type        = string
}

variable "deployment_container_endpoint" {
  description = "URL do container de blob que guarda o pacote de deploy, ex.: https://<conta>.blob.core.windows.net/<container>."
  type        = string
}

variable "host_storage_account_name" {
  description = "Storage account do host do Functions (AzureWebJobsStorage), acessada pela identidade da Function."
  type        = string
}

variable "runtime_name" {
  description = "Runtime da Function: python, node, dotnet-isolated, java, powershell ou custom."
  type        = string
  default     = "python"
}

variable "runtime_version" {
  description = "Versão do runtime, ex.: '3.13' para Python."
  type        = string
}

variable "instance_memory_in_mb" {
  description = "Memória por instância. 512 é o menor tamanho do Flex."
  type        = number
  default     = 512

  validation {
    condition     = contains([512, 2048, 4096], var.instance_memory_in_mb)
    error_message = "instance_memory_in_mb deve ser 512, 2048 ou 4096."
  }
}

variable "maximum_instance_count" {
  description = "Máximo de instâncias no scale-out. Valor baixo limita o custo em caso de pico ou abuso."
  type        = number
  default     = 1

  validation {
    condition     = var.maximum_instance_count >= 1 && var.maximum_instance_count <= 1000
    error_message = "maximum_instance_count deve estar entre 1 e 1000."
  }
}

variable "http_concurrency" {
  description = "Requisições HTTP simultâneas por instância. null = padrão da plataforma, que em Python é 1 e faz cada sobreposição abrir uma instância nova."
  type        = number
  default     = null

  validation {
    condition     = var.http_concurrency == null || (var.http_concurrency >= 1 && var.http_concurrency <= 1000)
    error_message = "http_concurrency deve estar entre 1 e 1000."
  }
}

variable "app_settings" {
  description = "App settings da aplicação. Nunca coloque segredos aqui: use managed identity."
  type        = map(string)
  default     = {}
}

variable "auth_mode" {
  description = "Vira o app setting AUTH_MODE. \"entra\" (padrão) responde 401 até o Entra ID existir; \"dev-anonymous\" aceita a organização pela query string e só pode ser usado em dev, com dados fictícios."
  type        = string
  default     = "entra"

  validation {
    condition     = contains(["entra", "dev-anonymous"], var.auth_mode)
    error_message = "auth_mode deve ser 'entra' ou 'dev-anonymous'."
  }
}

variable "app_insights_connection_string" {
  description = "Connection string do Application Insights."
  type        = string
  sensitive   = true
}

variable "cors_allowed_origins" {
  description = "Origens autorizadas a chamar a API pelo navegador, sem barra final."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
