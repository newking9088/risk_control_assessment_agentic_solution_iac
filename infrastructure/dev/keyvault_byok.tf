# =============================================================================
# keyvault_byok.tf — BYOK (Bring Your Own Key) Key Vault.
#
# Provisions customer-managed encryption keys consumed by:
#   Storage Account, PostgreSQL, Service Bus, Cognitive Services, Data Factory.
#
# Only deployed when: enabled_modules.byok = true
#
# Dependent modules (storage, postgres, etc.) check byok independently via
# their own for_each conditions; this vault must exist before they do.
#
# Placeholders in this file:
#   __TFE_HOSTNAME__       — Terraform Enterprise registry hostname
#   __TFE_ORG__            — Terraform Enterprise organization
#   __ORG_PUBLIC_IP_CIDR__ — Org egress CIDR, e.g. 203.0.113.0/24
# =============================================================================

# =============================================================================
# BYOK Key Vault
# =============================================================================
module "keyvault_byok" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/keyvault-byok/azurerm"
  version = "19.1.1-3-1.7"

  for_each = var.enabled_modules.byok ? toset(["byok_keyvault"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.security.keyvault_byok_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tenant_id           = var.__ngc.environment_details.system_parameters.TENANT_ID

  # Platform BYOK naming policy requires these fixed values.
  key_suffix   = "rad"
  production   = false
  subnet_group = "ctm_amer"
  cskcategory  = "global"

  # Provision a key for Cognitive Services CMK.
  # Add entries here when enabling additional CMK-backed resources.
  keys = ["cognitive"]

  network_acls = {
    bypass         : "AzureServices"
    default_action : "Deny"
    ip_rules       : ["__ORG_PUBLIC_IP_CIDR__"]
  }

  tags = local.tags
}

# =============================================================================
# BYOK Key Vault — Admin Access Policies
# =============================================================================
module "access_policies_byok_keyvault_admins" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  for_each = {
    for pair in setproduct(keys(var.keyvault_admins_byok), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      admin_name : pair[0]
      vault_key  : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = var.keyvault_admins_byok[each.value.admin_name]

  # WrapKey / UnwrapKey are required for CMK operations in addition to standard admin rights.
  key_permissions         : ["Backup", "Create", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Update", "WrapKey", "UnwrapKey"]
  secret_permissions      : ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
  certificate_permissions : ["Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"]
}

# =============================================================================
# Diagnostic Settings — BYOK Key Vault
# =============================================================================
module "diagnostic_settings_byok_keyvault" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  for_each = var.enabled_modules.diagnostic_logging ? module.keyvault_byok : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "AuditEvent",                  enabled : true },
    { category : "AzurePolicyEvaluationDetails", enabled : true },
  ]
}

# =============================================================================
# Outputs
# =============================================================================
output "outputs_keyvault_byok" {
  description = "BYOK Key Vault outputs."
  value = {
    keyvault_byok : { for i, p in module.keyvault_byok : i => {
      id        : p.id
      name      : p.name
      vault_uri : p.vault_uri
    }}
  }
}
