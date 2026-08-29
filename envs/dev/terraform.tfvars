subscription_id = "00000000-0000-0000-0000-000000000000" # TROQUE pela subscription de dev

environment    = "dev"
application    = "meuapp"
location       = "brazilsouth"
location_short = "brs"

address_space = ["10.10.0.0/16"]

subnets = {
  app = {
    address_prefixes = ["10.10.1.0/24"]
  }
  data = {
    address_prefixes  = ["10.10.2.0/24"]
    service_endpoints = ["Microsoft.Storage"]
  }
}

storage_replication_type = "LRS"

tags = {
  cost_center = "TI-001"
  owner       = "plataforma@empresa.com"
}
