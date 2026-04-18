# storage.tf — Azure Storage Account with HNS and customer-managed key (CMK).
#
# BYOK dependency chain (Section 3.5):
#   user_assigned_identity_storage
#     └─► access_policies_byok_storage   (grants WrapKey / UnwrapKey to identity)
#           └─► storage_accounts         (CMK references identity + BYOK key)
#                 └─► time_sleep_storage (30 s — lets CMK binding propagate)
#                       └─► key_vault_secrets_storage
#
# storage_containers and diagnostic_settings branch off storage_accounts directly.
#
# Only deployed when: enabled_modules.storage_account = true
#
# Placeholders in this file:
#   west.tfe.nginternal.com       — Terraform Enterprise registry hostname
#   platform            — Terraform Enterprise organization

# User-Assigned Managed Identity — Storage
# The storage account uses this identity to access the BYOK key vault for CMK.
module "user_assigned_identity_storage" {
  source  = "west.tfe.nginternal.com/platform/user-assigned-identity/azurerm"
  version = "4.1.0-3-1.7"

  for_each = var.enabled_modules.storage_account ? toset(["storage"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.identity.storage_identity_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tags                = local.tags
}

# BYOK Access Policy — Storage Identity
# Grants the storage managed identity the minimum permissions required for CMK:
# Get (read key metadata), WrapKey (encrypt data key), UnwrapKey (decrypt data key).
module "access_policies_byok_storage" {
  source  = "west.tfe.nginternal.com/platform/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  # Cross-product: one policy entry per identity instance per BYOK vault instance.
  for_each = {
    for pair in setproduct(keys(module.user_assigned_identity_storage), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      identity_key : pair[0]
      vault_key    : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = module.user_assigned_identity_storage[each.value.identity_key].principal_id

  key_permissions         : ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions      : []
  certificate_permissions : []
}

# Storage Account
module "storage_accounts" {
  source  = "west.tfe.nginternal.com/platform/storage-account/azurerm"
  version = "15.4.2-3-1.7"

  for_each = var.enabled_modules.storage_account ? {
    app_storage : {
      name : var.__ngc.environment_details.user_parameters.naming_service.storage.storage_account_name
    }
  } : {}

  name                = each.value.name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Hierarchical namespace enables Azure Data Lake Storage Gen2 capabilities.
  is_hns_enabled = true

  network_rules = {
    default_action             : "Deny"
    bypass                     : ["AzureServices"]
    ip_rules                   : var.org_public_ip_cidrs
    virtual_network_subnet_ids : [var.aks_subnet_id]
  }

  # CMK encryption — only wired when BYOK vault exists.
  # The identity must have WrapKey/UnwrapKey on the BYOK vault before this runs.
  customer_managed_key = var.enabled_modules.byok ? {
    key_vault_key_id          : module.keyvault_byok["byok_keyvault"].cognitive_key_id
    user_assigned_identity_id : module.user_assigned_identity_storage["storage"].id
  } : null

  identity = {
    type         : "UserAssigned"
    identity_ids : [module.user_assigned_identity_storage["storage"].id]
  }

  tags = local.tags

  # Access policy propagation must complete before the storage account
  # attempts to use the CMK key from the BYOK vault.
  depends_on = [module.access_policies_byok_storage]
}

# Storage Containers
module "storage_containers" {
  source  = "west.tfe.nginternal.com/platform/storage-container/azurerm"
  version = "10.0.0-3-1.7"

  for_each = module.storage_accounts

  storage_account_name = each.value.name
  name                 = var.__ngc.environment_details.user_parameters.naming_service.storage.container_name
  container_access_type = "private"
}

# Time Sleep — Storage
# Waits 30 s after storage account creation before secrets are read.
# Ensures the CMK binding has fully propagated to all Azure storage endpoints.
module "time_sleep_storage" {
  source  = "west.tfe.nginternal.com/platform/time-sleep/time"
  version = "2.0.0-3-1.7"

  for_each        = module.storage_accounts
  create_duration = "30s"

  depends_on = [module.storage_accounts]
}

# Diagnostic Settings — Storage Account (per sub-service)
# Azure storage diagnostics are attached to each sub-service endpoint separately,
# not to the storage account resource itself.
module "diagnostic_settings_storage_accounts" {
  source  = "west.tfe.nginternal.com/platform/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  # Cross-product: one diagnostic setting per storage account per sub-service.
  for_each = var.enabled_modules.diagnostic_logging ? {
    for pair in setproduct(
      keys(module.storage_accounts),
      ["blobServices", "queueServices", "tableServices", "fileServices"]
    ) :
    format("%s_%s", pair[0], pair[1]) => {
      storage_key  : pair[0]
      sub_service  : pair[1]
    }
  } : {}

  name = format(
    "m-diag-%s-%s",
    module.storage_accounts[each.value.storage_key].name,
    each.value.sub_service
  )

  # Target the sub-service endpoint, e.g. <account_id>/blobServices/default
  target_resource_id = format(
    "%s/%s/default",
    module.storage_accounts[each.value.storage_key].id,
    each.value.sub_service
  )

  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "StorageRead",   enabled : true },
    { category : "StorageWrite",  enabled : true },
    { category : "StorageDelete", enabled : true },
  ]
}

# Key Vault Secrets — Storage
module "key_vault_secrets_storage" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.storage_accounts
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "STORAGE-PRIMARY-CONNECTION-STRING" : {
      name            : "STORAGE-PRIMARY-CONNECTION-STRING"
      value           : each.value.primary_connection_string
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }

  depends_on = [module.time_sleep_storage]
}

# Outputs
output "outputs_storage" {
  description = "Storage Account outputs."
  value = {
    storage_accounts : { for i, p in module.storage_accounts : i => {
      id   : p.id
      name : p.name
    }}
  }
}
