# =============================================================================
# synapse.tf — Azure Synapse Analytics (workspace + SQL pool + Spark pool).
#
# Dependency chain:
#   sql_server_random_passwords
#     └─► synapse_workspace     (uses random admin password + app storage account)
#           ├─► synapse_sql_pool
#           ├─► synapse_sql_post  (Spark pool — same module, different version)
#           ├─► synapse_role_assignment
#           └─► key_vault_secrets_synapse
#
# Synapse firewall rules are defined in a locals block grouped by geographic
# region to keep the workspace block readable.
#
# Only deployed when: enabled_modules.synapse = true
#
# Placeholders in this file:
#   __TFE_HOSTNAME__                   — Terraform Enterprise registry hostname
#   __TFE_ORG__                        — Terraform Enterprise organization
#   __SYNAPSE_INDIA_WEST_IP_START__    — First IP of India West access range
#   __SYNAPSE_INDIA_WEST_IP_END__      — Last IP of India West access range
#   __SYNAPSE_US_WEST_IP_START__       — First IP of US West access range
#   __SYNAPSE_US_WEST_IP_END__         — Last IP of US West access range
#   __SYNAPSE_US_CENTRAL_IP_START__    — First IP of US Central access range
#   __SYNAPSE_US_CENTRAL_IP_END__      — Last IP of US Central access range
#   __AKS_IP_START__                   — First IP of AKS node pool subnet
#   __AKS_IP_END__                     — Last IP of AKS node pool subnet
#   __ORG_PUBLIC_IP_START__            — First IP of org public range
#   __ORG_PUBLIC_IP_END__              — Last IP of org public range
# =============================================================================

# =============================================================================
# Locals — Synapse Firewall Rules
# =============================================================================
# Grouped by region so new ranges can be added without touching the workspace block.
locals {
  synapse_firewall_rules = var.enabled_modules.synapse ? {
    aks_nodes : {
      start_ip_address : "__AKS_IP_START__"
      end_ip_address   : "__AKS_IP_END__"
    }
    org_public : {
      start_ip_address : "__ORG_PUBLIC_IP_START__"
      end_ip_address   : "__ORG_PUBLIC_IP_END__"
    }
    india_west : {
      start_ip_address : "__SYNAPSE_INDIA_WEST_IP_START__"
      end_ip_address   : "__SYNAPSE_INDIA_WEST_IP_END__"
    }
    us_west : {
      start_ip_address : "__SYNAPSE_US_WEST_IP_START__"
      end_ip_address   : "__SYNAPSE_US_WEST_IP_END__"
    }
    us_central : {
      start_ip_address : "__SYNAPSE_US_CENTRAL_IP_START__"
      end_ip_address   : "__SYNAPSE_US_CENTRAL_IP_END__"
    }
  } : {}
}

# =============================================================================
# Random Password — Synapse SQL Admin
# =============================================================================
module "sql_server_random_passwords" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/random-password/random"
  version = "3.0.0-3-1.7"

  for_each = var.enabled_modules.synapse ? toset(["synapse_admin"]) : toset([])

  length      = 25
  min_upper   = 4
  min_lower   = 4
  min_numeric = 4
  min_special = 4
}

# =============================================================================
# Synapse Analytics Workspace
# =============================================================================
module "synapse_workspace" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/synapse-workspace/azurerm"
  version = "5.0.3-3-1.7"

  for_each = var.enabled_modules.synapse ? toset(["app_synapse"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.analytics.synapse_workspace_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # Synapse uses the application storage account (ADLS Gen2) as its primary data lake.
  # The storage account must be deployed before Synapse (enabled_modules.storage_account = true).
  storage_data_lake_gen2_filesystem_id = module.storage_containers["app_storage"].id

  sql_administrator_login          = var.__ngc.environment_details.user_parameters.naming_service.analytics.synapse_admin_user
  sql_administrator_login_password = module.sql_server_random_passwords["synapse_admin"].result

  # Managed VNet is disabled to allow direct connectivity to the existing VNet.
  managed_virtual_network_enabled = false

  # Firewall rules are sourced from the regional locals block above.
  firewall_rules = local.synapse_firewall_rules

  # Grant the platform admins group Storage Blob Data Contributor on the data lake.
  storage_blob_data_contributors = var.platform_admins

  tags = local.tags

  depends_on = [module.sql_server_random_passwords]
}

# =============================================================================
# Synapse SQL Dedicated Pool
# =============================================================================
module "synapse_sql_pool" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/synapse-sql-pool/azurerm"
  version = "3.1.0-3-1.7"

  for_each = module.synapse_workspace

  synapse_workspace_id = each.value.id
  name                 = var.__ngc.environment_details.user_parameters.naming_service.analytics.synapse_sql_pool_name

  # DW100c is the smallest SKU — suitable for dev/qa; scale up via config.auto.tfvars for prod.
  sku_name = "DW100c"

  # Encryption is managed at the workspace level; pool-level encryption is redundant here.
  data_encrypted = false

  tags = local.tags
}

# =============================================================================
# Synapse Spark Pool
# =============================================================================
# Named "synapse_sql_post" per module inventory — uses the pool module v5.1.1
# which supports Apache Spark configuration.
module "synapse_sql_post" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/synapse-sql-pool/azurerm"
  version = "5.1.1-3-1.7"

  for_each = module.synapse_workspace

  synapse_workspace_id = each.value.id
  name                 = var.__ngc.environment_details.user_parameters.naming_service.analytics.synapse_spark_pool_name

  node_size_family = "MemoryOptimized"
  node_size        = "Small"
  node_count       = 4

  spark_version = "3.4"

  # Auto-pause after 6 minutes of inactivity to reduce idle compute costs.
  auto_pause = {
    delay_in_minutes : 6
  }

  # Session-level packages allow notebook authors to pip-install without
  # rebuilding the pool image.
  session_level_packages_enabled = true

  tags = local.tags
}

# =============================================================================
# Synapse Role Assignments
# =============================================================================
module "synapse_role_assignment" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/synapse-role-assignment/azurerm"
  version = "7.0.0-3-1.7"

  # One assignment per entry in var.synapse_users, per workspace instance.
  for_each = {
    for pair in setproduct(keys(var.synapse_users), keys(module.synapse_workspace)) :
    format("%s_%s", pair[0], pair[1]) => {
      user_key      : pair[0]
      workspace_key : pair[1]
    }
  }

  synapse_workspace_id = module.synapse_workspace[each.value.workspace_key].id
  role_name            = var.synapse_users[each.value.user_key].role_name
  principal_id         = var.synapse_users[each.value.user_key].principal_id
}

# =============================================================================
# Key Vault Secrets — Synapse
# =============================================================================
module "key_vault_secrets_synapse" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.synapse_workspace
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "SYNAPSE-ADMIN-USER" : {
      name            : "SYNAPSE-ADMIN-USER"
      value           : each.value.sql_administrator_login
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "SYNAPSE-ADMIN-PASSWORD" : {
      name            : "SYNAPSE-ADMIN-PASSWORD"
      value           : module.sql_server_random_passwords["synapse_admin"].result
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "outputs_synapse" {
  description = "Synapse Analytics outputs."
  value = {
    synapse_workspace : { for i, p in module.synapse_workspace : i => {
      id                             : p.id
      name                           : p.name
      connectivity_endpoints         : p.connectivity_endpoints
    }}
  }
}
