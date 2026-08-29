# Subscription única (Azure for Students) — os 3 ambientes se isolam por
# resource group + RBAC, não por subscription. Veja bootstrap/bootstrap.sh.
subscription_id = "dc05b302-9b10-4421-98ab-054114fb6bed"

environment    = "prd"
application    = "meuapp"
location       = "brazilsouth"
location_short = "brs"

address_space = ["10.30.0.0/16"]

subnets = {
  app = {
    address_prefixes = ["10.30.1.0/24"]
  }
  data = {
    address_prefixes  = ["10.30.2.0/24"]
    service_endpoints = ["Microsoft.Storage"]
  }
}

storage_replication_type = "GZRS"

tags = {
  cost_center = "TI-001"
  owner       = "plataforma@empresa.com"
}
