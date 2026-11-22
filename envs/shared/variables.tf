variable "subscription_id" {
  description = "Subscription cujo Activity Log é exportado. Hoje é a única, compartilhada por dev, stg e prd."
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Workspace do Log Analytics que recebe o Activity Log."
  type        = string
}

variable "log_analytics_workspace_resource_group" {
  description = "Resource group do workspace. Ele é criado e gerenciado pela raiz do ambiente que o possui."
  type        = string
}

variable "security_contact_emails" {
  description = "E-mails que recebem os alertas de alta severidade do Defender for Cloud. Lista vazia = sem contato. Defina em um *.auto.tfvars (ignorado pelo Git), nunca no código."
  type        = list(string)
  default     = []
}

variable "activity_log_categories" {
  description = "Categorias do Activity Log exportadas para a tabela AzureActivity."
  type        = list(string)
  default     = ["Administrative", "Security", "Policy", "Alert"]
}
