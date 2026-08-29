terraform {
  # Os placeholders __*__ são preenchidos por bootstrap/bootstrap.sh.
  backend "azurerm" {
    resource_group_name  = "__STATE_RESOURCE_GROUP__"
    storage_account_name = "__STATE_STORAGE_ACCOUNT__"
    container_name       = "tfstate"
    key                  = "prd.terraform.tfstate"

    # Sem chave de conta: autenticação via Entra ID / OIDC.
    use_azuread_auth = true
  }
}
