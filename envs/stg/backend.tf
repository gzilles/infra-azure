terraform {
  # Os placeholders __*__ são preenchidos por bootstrap/bootstrap.sh.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-meuapp"
    storage_account_name = "stmeuapptfstate15384"
    container_name       = "tfstate"
    key                  = "stg.terraform.tfstate"

    # Sem chave de conta: autenticação via Entra ID / OIDC.
    use_azuread_auth = true
  }
}
