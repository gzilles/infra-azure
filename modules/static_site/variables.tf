variable "name" {
  description = "Nome da storage account do site. Globalmente único, 3-24 caracteres, apenas minúsculas e dígitos."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Nome inválido: use 3-24 caracteres, somente letras minúsculas e dígitos."
  }
}

variable "resource_group_name" {
  description = "Resource group onde a storage account do site será criada."
  type        = string
}

variable "location" {
  description = "Região da Azure."
  type        = string
}

variable "index_document" {
  description = "Documento servido na raiz do site."
  type        = string
  default     = "index.html"
}

variable "error_404_document" {
  description = "Documento servido em 404. Apontar para o index permite o roteamento client-side de uma SPA."
  type        = string
  default     = "index.html"
}

variable "log_analytics_workspace_id" {
  description = "Workspace do Log Analytics que recebe os logs de leitura, escrita e exclusão de blobs do site. null = nenhum diagnostic setting."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo."
  type        = map(string)
  default     = {}
}
