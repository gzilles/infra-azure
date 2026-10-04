variable "application" {
  description = "Nome curto da aplicação. Compõe a categoria das consultas (\"Security - <application>\")."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace do Log Analytics onde as consultas são salvas e executadas."
  type        = string
}

variable "expected_cosmos_principal_ids" {
  description = "Object IDs autorizados a ler o Cosmos pelo plano de dados (ex.: a identidade da Function). Qualquer outro aparece na consulta de principal inesperado."
  type        = list(string)
}

variable "static_site_storage_account_name" {
  description = "Storage account do site estático, vigiada para escrita e exclusão no $web."
  type        = string
}

variable "host_storage_account_name" {
  description = "Storage account do host e do deploy da Function, onde fica o container do pacote."
  type        = string
}

variable "deployment_container_name" {
  description = "Container que recebe o pacote de deploy da Function."
  type        = string
  default     = "func-deploy"
}

variable "function_app_name" {
  description = "Nome da Function App, usado na consulta de deploys."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo."
  type        = map(string)
  default     = {}
}
