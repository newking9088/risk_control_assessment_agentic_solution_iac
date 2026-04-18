# =============================================================================
# data_factory.tf — Azure Data Factory (CMK, managed private endpoint).
#
# BYOK dependency chain (Section 3.5):
#   user_assigned_identity_data_factory
#     └─► access_policies_byok_data_factory   (grants WrapKey / UnwrapKey)
#           └─► data_factory                  (CMK, depends_on access policy)
#                 ├─► key_vault_secrets_data_factory
#                 └─► data_factory_managed_private_endpoint_postgres
#                       (only when BOTH data_factory AND postgres are enabled)
#
# No time_sleep module is listed for Data Factory — depends_on the access
# policy directly. If CMK binding errors occur at plan time, add a
# time-sleep/time module between access_policies and data_factory.
#
# Only deployed when: enabled_modules.data_factory = true
# Managed PE to Postgres also requires: enabled_modules.postgres = true
#
# Placeholders in this file:
#   __TFE_HOSTNAME__ — Terraform Enterprise registry hostname
#   __TFE_ORG__      — Terraform Enterprise organization
# =============================================================================

# =============================================================================
# User-Assigned Managed Identity — Data Factory
# =============================================================================
module "user_assigned_identity_data_factory" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/user-assigned-identity/azurerm"
  version = "4.1.0-3-1.7"

  for_each = var.enabled_modules.data_factory ? toset(["data_factory"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.identity.data_factory_identity_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tags                = local.tags
}

# =============================================================================
# BYOK Access Policy — Data Factory Identity
# =============================================================================
module "access_policies_byok_data_factory" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  for_each = {
    for pair in setproduct(keys(module.user_assigned_identity_data_factory), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      identity_key : pair[0]
      vault_key    : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = module.user_assigned_identity_data_factory[each.value.identity_key].principal_id

  key_permissions         : ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions      : []
  certificate_permissions : []
}

# =============================================================================
# Data Factory
# =============================================================================
module "data_factory" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/data-factory/azurerm"
  version = "12.0.0-3-1.7"

  for_each = var.enabled_modules.data_factory ? toset(["app_adf"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.integration.data_factory_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # Managed virtual network isolates ADF integration runtimes from the public internet.
  managed_virtual_network_enabled = true

  # Private endpoint subnet for the ADF managed runtime.
  managed_private_endpoint_subnet_id = data.azurerm_subnet.subnet[var.enabled_modules.data_factory_subnet].id

  # UserAssigned identity is required for CMK access via the BYOK vault.
  identity = {
    type         : "UserAssigned"
    identity_ids : [module.user_assigned_identity_data_factory["data_factory"].id]
  }

  # CMK encryption via BYOK vault — only wired when byok is enabled.
  customer_managed_key = var.enabled_modules.byok ? {
    key_vault_key_id          : module.keyvault_byok["byok_keyvault"].cognitive_key_id
    identity_client_id        : module.user_assigned_identity_data_factory["data_factory"].client_id
  } : null

  tags = local.tags

  depends_on = [module.access_policies_byok_data_factory]
}

# =============================================================================
# Managed Private Endpoint — PostgreSQL
# =============================================================================
# Connects the ADF managed virtual network to the PostgreSQL Flexible Server.
# Only created when BOTH data_factory AND postgres are enabled, so that the
# PostgreSQL server ID is always available when this resource is created.
module "data_factory_managed_private_endpoint_postgres" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/data-factory-managed-private-endpoint/azurerm"
  version = "2.0.0-3-1.7"

  # Conditional cross-product: empty map when either module is disabled.
  for_each = (var.enabled_modules.data_factory && var.enabled_modules.postgres) ? {
    for pair in setproduct(keys(module.data_factory), keys(module.postgres)) :
    format("%s_%s", pair[0], pair[1]) => {
      adf_key      : pair[0]
      postgres_key : pair[1]
    }
  } : {}

  data_factory_id    = module.data_factory[each.value.adf_key].id
  name               = format("pe-%s-postgres", module.data_factory[each.value.adf_key].name)
  target_resource_id = module.postgres[each.value.postgres_key].id
  subresource_name   = "postgresqlServer"
}

# =============================================================================
# Key Vault Secrets — Data Factory
# =============================================================================
module "key_vault_secrets_data_factory" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.data_factory
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "DATA-FACTORY-NAME" : {
      name            : "DATA-FACTORY-NAME"
      value           : each.value.name
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "DATA-FACTORY-ID" : {
      name            : "DATA-FACTORY-ID"
      value           : each.value.id
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
output "outputs_data_factory" {
  description = "Data Factory outputs."
  value = {
    data_factory : { for i, p in module.data_factory : i => {
      id   : p.id
      name : p.name
    }}
  }
}
