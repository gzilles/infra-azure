subscription_id = "00000000-0000-0000-0000-000000000000" # TROQUE pela subscription de staging

environment    = "stg"
application    = "meuapp"
location       = "brazilsouth"
location_short = "brs"

address_space = ["10.20.0.0/16"]

subnets = {
  app = {
    address_prefixes = ["10.20.1.0/24"]
  }
  data = {
    address_prefixes  = ["10.20.2.0/24"]
    service_endpoints = ["Microsoft.Storage"]
  }
}

storage_replication_type = "ZRS"

tags = {
  cost_center = "TI-001"
  owner       = "plataforma@empresa.com"
}
