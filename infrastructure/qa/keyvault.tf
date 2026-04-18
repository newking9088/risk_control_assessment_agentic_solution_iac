# keyvault.tf — Application Key Vault (MANDATORY).
#
# This vault is always deployed regardless of enabled_modules.
# It is the single secret store: every other module writes its connection
# strings and keys here via the key-vault-secret module.
#
# Placeholders in this file:
#   platform            — Terraform Enterprise organization

# Application Key Vault
module "keyvault" {
  source  = "west.tfe.nginternal.com/platform/keyvault/azurerm"
  version = "12.0.3-3-1.7"

  # Mandatory module — always create exactly one vault instance.
  for_each = toset(["app_keyvault"])

  name                = var.__ngc.environment_details.user_parameters.naming_service.security.keyvault_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tenant_id           = var.__ngc.environment_details.system_parameters.TENANT_ID
  sku_name            = "standard"

  # Prevent accidental permanent deletion of the vault and all its secrets.
  purge_protection_enabled = true

  # TFE team instance is required by the module for registry authentication at plan time.
  tfe_hostname = var.__ngc.environment_details.system_parameters.TFE_TEAM.team_instance

  network_acls = {
    bypass         : "AzureServices"
    default_action : "Deny"
    # Allow org egress traffic and AKS nodes to reach the vault.
    ip_rules                   : var.org_public_ip_cidrs
    virtual_network_subnet_ids : [var.aks_subnet_id]
  }

  # Inline policies for the two platform service principals.
  # Human admin policies are managed below via the access-policy module
  # to keep this block stable and avoid unnecessary plan diffs when admins change.
  access_policies = [
    {
      # Deployment SPM: full permissions required for CI/CD secret writes.
      object_id               : var.spn_object_id
      key_permissions         : ["Backup", "Create", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Update"]
      secret_permissions      : ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
      certificate_permissions : ["Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"]
    },
    {
      # AKS SPM: read-only at pod runtime via CSI secrets driver.
      object_id               : var.aks_spn_object_id
      key_permissions         : ["Backup", "Create", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Update"]
      secret_permissions      : ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
      certificate_permissions : ["Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"]
    },
  ]

  tags = local.tags
}

# Application Key Vault — Admin Access Policies
# Creates one access policy per admin per vault instance.
# Admin entries come from var.keyvault_admins_app (set in config.auto.tfvars).
module "access_policies_app_keyvault_admins" {
  source  = "west.tfe.nginternal.com/platform/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  # Cross-product of admin names and vault keys (only one vault, but kept
  # generic in case a second vault is added later without changing the pattern).
  for_each = {
    for pair in setproduct(keys(var.keyvault_admins_app), keys(module.keyvault)) :
    format("%s_%s", pair[0], pair[1]) => {
      admin_name : pair[0]
      vault_key  : pair[1]
    }
  }

  key_vault_id = module.keyvault[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = var.keyvault_admins_app[each.value.admin_name]

  key_permissions         = ["Backup", "Create", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Update"]
  secret_permissions      = ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
  certificate_permissions = ["Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"]
}

# Diagnostic Settings — Application Key Vault
module "diagnostic_settings_app_keyvault" {
  source  = "west.tfe.nginternal.com/platform/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  # Only created when diagnostic_logging is enabled.
  for_each = var.enabled_modules.diagnostic_logging ? module.keyvault : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "AuditEvent",                  enabled : true },
    { category : "AzurePolicyEvaluationDetails", enabled : true },
  ]
}

# Outputs
output "outputs_keyvault" {
  description = "Application Key Vault outputs."
  value = {
    keyvault : { for i, p in module.keyvault : i => {
      id        : p.id
      name      : p.name
      vault_uri : p.vault_uri
    }}
  }
}
