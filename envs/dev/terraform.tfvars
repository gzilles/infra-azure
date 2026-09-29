# Subscription única (Azure for Students) — os 3 ambientes se isolam por
# resource group + RBAC, não por subscription. Veja bootstrap/bootstrap.sh.
subscription_id = "dc05b302-9b10-4421-98ab-054114fb6bed"

environment    = "dev"
application    = "meuapp"
location       = "brazilsouth"
location_short = "brs"

address_space = ["10.10.0.0/16"]

subnets = {
  app = {
    address_prefixes  = ["10.10.1.0/24"]
    service_endpoints = ["Microsoft.Storage", "Microsoft.AzureCosmosDB"]
    # Exigida pela VNet integration do Functions Flex Consumption.
    delegation = {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  data = {
    address_prefixes  = ["10.10.2.0/24"]
    service_endpoints = ["Microsoft.Storage"]
  }
}

storage_replication_type = "LRS"

log_analytics_daily_quota_gb = 0.1

tags = {
  cost_center = "TI-001"
  owner       = "plataforma@empresa.com"
}
