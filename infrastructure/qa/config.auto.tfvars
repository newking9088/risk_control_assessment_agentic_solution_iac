# Edit this file (and databricks/config.auto.tfvars) to onboard a new environment.
# Nothing else under infrastructure/dev/ should need changes.


# — Azure identity used by Terraform & AKS —
spn_object_id       = "143363ce-d4c5-4c0d-b3d9-84d5c252bc97"
aks_spn_object_id   = "e272c41e-0ecf-4e75-98fd-d290fd2d3bc1"
org_public_ip_cidrs = ["155.201.0.0/16"]

# — AKS subnet ARM path (non-prod: shared by dev, qa, stage) —
aks_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-network-nonprod/providers/Microsoft.Network/virtualNetworks/vnet-nonprod/subnets/snet-aks"

database_name = "appdb"

# — Module on/off switches — all default to disabled; enable incrementally —
enabled_modules = {
  byok               = false
  diagnostic_logging = false

  storage_account = false

  redis_cache  = false
  redis_subnet = null

  cognitive_account = false
  cognitive_subnet  = null

  service_bus    = false
  search_service = false

  postgres        = false
  postgres_subnet = null

  databricks                         = false
  databricks_private_subnet          = null
  databricks_public_subnet           = null
  databricks_private_endpoint_subnet = null

  data_factory        = false
  data_factory_subnet = null

  synapse = false
}

# — Single admin (clone, then add your team) —
keyvault_admins_app = {
  raj_paudel = "00000000-0000-0000-0000-000000000002"
}

keyvault_admins_byok = {
  raj_paudel = "00000000-0000-0000-0000-000000000002"
}
