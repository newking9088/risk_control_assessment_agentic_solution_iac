# postgres.tf — Azure PostgreSQL Flexible Server (v16, GP SKU, CMK).
#
# BYOK dependency chain (Section 3.5):
#   user_assigned_identity_postgres
#     └─► access_policies_byok_postgres  (grants WrapKey / UnwrapKey to identity)
#           └─► time_sleep_postgres      (30 s — policy propagation)
#                 └─► postgres           (CMK references identity + BYOK key)
#                       ├─► postgres_flexible_databases
#                       ├─► private_endpoints_postgres
#                       ├─► diagnostic_settings_postgres  (diagnostic_logging)
#                       └─► key_vault_secrets_postgres
#
# Only deployed when: enabled_modules.postgres = true
# Private endpoint also requires: enabled_modules.postgres_subnet (subnet key string)
#
# Placeholders in this file:
#   platform                — Terraform Enterprise organization

# User-Assigned Managed Identity — PostgreSQL
module "user_assigned_identity_postgres" {
  source  = "west.tfe.nginternal.com/platform/user-assigned-identity/azurerm"
  version = "4.1.0-3-1.7"

  for_each = var.enabled_modules.postgres ? toset(["postgres"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.identity.postgres_identity_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tags                = local.tags
}

# BYOK Access Policy — PostgreSQL Identity
module "access_policies_byok_postgres" {
  source  = "west.tfe.nginternal.com/platform/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  for_each = {
    for pair in setproduct(keys(module.user_assigned_identity_postgres), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      identity_key : pair[0]
      vault_key    : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = module.user_assigned_identity_postgres[each.value.identity_key].principal_id

  key_permissions         = ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions      = []
  certificate_permissions = []
}

# Time Sleep — PostgreSQL
# Azure AD policy replication can take up to 30 s.
# PostgreSQL will fail to create if the identity cannot yet access the BYOK key.
module "time_sleep_postgres" {
  source  = "west.tfe.nginternal.com/platform/time-sleep/time"
  version = "2.0.0-3-1.7"

  for_each        = module.user_assigned_identity_postgres
  create_duration = "30s"

  depends_on = [module.access_policies_byok_postgres]
}

# Random Password — PostgreSQL Admin
# Generates a 25-char password with enforced character variety.
# The result (a string) is passed to the postgres module's administrator_password.
module "postgres_random_passwords" {
  source  = "west.tfe.nginternal.com/platform/random-password/random"
  version = "3.0.0-3-1.7"

  for_each = var.enabled_modules.postgres ? toset(["app_postgres"]) : toset([])

  length      = 25
  min_upper   = 4
  min_lower   = 4
  min_numeric = 4
  min_special = 4
}

# PostgreSQL Flexible Server
module "postgres" {
  source  = "west.tfe.nginternal.com/platform/postgresql-flexible/azurerm"
  version = "6.1.0-3-1.7"

  for_each = var.enabled_modules.postgres ? toset(["app_postgres"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.database.postgres_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # PostgreSQL 16 with the general-purpose D2ds_v5 compute SKU.
  # 65536 MB storage provides headroom for audit logs and vector indexes.
  postgresql_version = "16"
  sku_name           = "GP_Standard_D2ds_v5"
  storage_mb         = 65536

  # Enable both Azure AD and password auth to support both managed identity
  # connections (services) and direct admin access (migrations, break-glass).
  authentication = {
    active_directory_auth_enabled : true
    password_auth_enabled         : true
  }

  administrator_login    = var.__ngc.environment_details.user_parameters.naming_service.database.postgres_admin_user
  administrator_password = module.postgres_random_passwords[each.key].result

  # Server-level extensions and connection pooler.
  # VECTOR enables pgvector for embedding storage.
  server_configuration = {
    "azure.extensions" : "CUBE,CITEXT,BTREE_GIST,VECTOR,UUID-OSSP"
    "pgbouncer.enabled" : "true"
  }

  # Scheduled maintenance on Monday at midnight minimises weekday disruption.
  maintenance_window = {
    day_of_week  : 1
    start_hour   : 0
    start_minute : 0
  }

  # Firewall rules restrict server-level access.
  # Private endpoint handles pod-level access; these rules cover ops / break-glass.
  firewall_rules = {
    aks_nodes : {
      start_ip_address : "10.200.0.0"
      end_ip_address   : "10.200.255.255"
    }
    org_global : {
      start_ip_address : "155.201.0.0"
      end_ip_address   : "155.201.255.255"
    }
  }

  # NSG rules are derived from the delegated postgres subnet's associated NSG.
  delegated_subnet_id = data.azurerm_subnet.subnet[var.enabled_modules.postgres_subnet].id
  nsg_rules           = data.azurerm_subnet.subnet[var.enabled_modules.postgres_subnet].network_security_group_id

  # CMK encryption via BYOK vault.
  customer_managed_key = var.enabled_modules.byok ? {
    key_vault_key_id                     : module.keyvault_byok["byok_keyvault"].cognitive_key_id
    primary_user_assigned_identity_id    : module.user_assigned_identity_postgres["postgres"].id
    geo_backup_user_assigned_identity_id : module.user_assigned_identity_postgres["postgres"].id
  } : null

  identity = var.enabled_modules.byok ? {
    type         : "UserAssigned"
    identity_ids : [module.user_assigned_identity_postgres["postgres"].id]
  } : null

  tags = local.tags

  depends_on = [module.time_sleep_postgres, module.postgres_random_passwords]
}

# PostgreSQL Flexible Database
module "postgres_flexible_databases" {
  source  = "west.tfe.nginternal.com/platform/postgresql-flexible-server-database/azurerm"
  version = "4.0.0-3-1.7"

  for_each = module.postgres

  server_id   = each.value.id
  name        = var.database_name
  charset     = "UTF8"
  collation   = "en_US.utf8"
}

# Private Endpoint — PostgreSQL
module "private_endpoints_postgres" {
  source  = "west.tfe.nginternal.com/platform/private-endpoint/azurerm"
  version = "5.1.1-3-1.7"

  for_each = module.postgres

  name                           = each.key
  location                       = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name            = data.azurerm_resource_group.app_env_resource_group.group_name
  subnet_id                      = data.azurerm_subnet.subnet[var.enabled_modules.postgres_subnet].id
  private_connection_resource_id = each.value.id
  subresources                   = ["postgresqlServer"]
  request_message                = "PL"
  tags                           = local.tags
}

# Diagnostic Settings — PostgreSQL
module "diagnostic_settings_postgres" {
  source  = "west.tfe.nginternal.com/platform/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  for_each = var.enabled_modules.diagnostic_logging ? module.postgres : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "PostgreSQLLogs",       enabled : true },
    { category : "PostgreSQLFlexSessions", enabled : true },
  ]
}

# Key Vault Secrets — PostgreSQL
module "key_vault_secrets_postgres" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.postgres
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "DB-HOST" : {
      name            : "DB-HOST"
      value           : each.value.fqdn
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "DB-ADMIN-USER-NAME" : {
      name            : "DB-ADMIN-USER-NAME"
      value           : each.value.administrator_login
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "DB-PORT" : {
      name            : "DB-PORT"
      value           : "5432"
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "DB-ADMIN-PASSWORD" : {
      name            : "DB-ADMIN-PASSWORD"
      value           : each.value.administrator_password
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "ADMIN-DATABASE-URL" : {
      name            : "ADMIN-DATABASE-URL"
      value           : format("postgresql://%s:%s@%s:5432/%s?sslmode=require", each.value.administrator_login, each.value.administrator_password, each.value.fqdn, var.database_name)
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# Outputs
output "outputs_postgres" {
  description = "PostgreSQL Flexible Server outputs."
  value = {
    postgres : { for i, p in module.postgres : i => {
      id   : p.id
      name : p.name
      fqdn : p.fqdn
    }}
  }
}
