# databricks.tf — Azure Databricks Workspace (infrastructure encryption + CMK).
#
# Databricks manages its own private endpoint subnet internally — no separate
# private-endpoint module is needed here (unlike Redis / Postgres / Cognitive).
#
# Dependency chain:
#   databricks_workspace
#     └─► key_vault_secrets_databricks
#
# Databricks user / group management lives in the separate Terraform root at
# infrastructure/<env>/databricks/ and runs after this workspace is provisioned.
#
# Only deployed when: enabled_modules.databricks = true
# Subnets required:
#   enabled_modules.databricks_private_subnet          — integration private subnet key
#   enabled_modules.databricks_public_subnet           — integration public subnet key
#   enabled_modules.databricks_private_endpoint_subnet — private endpoint subnet key
#
# Placeholders in this file:
#   platform      — Terraform Enterprise organization

# Databricks Workspace
module "databricks_workspace" {
  source  = "west.tfe.nginternal.com/platform/databricks-workspaces/azurerm"
  version = "12.1.1-3-1.7"

  for_each = var.enabled_modules.databricks ? toset(["app_databricks"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.analytics.databricks_workspace_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # Infrastructure encryption provides a second layer of AES-256 encryption
  # on the Databricks-managed storage and compute infrastructure.
  infrastructure_encryption_enabled = true

  # CMK encrypts the managed disk and DBFS root storage with a customer key.
  customer_managed_key_enabled = var.enabled_modules.byok

  # VNet injection subnets — Databricks creates an NSG on each and manages
  # the inbound/outbound rules required for cluster communication.
  custom_parameters = {
    virtual_network_id                                   : data.azurerm_subnet.subnet[var.enabled_modules.databricks_private_subnet].virtual_network_id
    private_subnet_name                                  : var.enabled_modules.databricks_private_subnet
    public_subnet_name                                   : var.enabled_modules.databricks_public_subnet
    private_subnet_network_security_group_association_id : data.azurerm_subnet.subnet[var.enabled_modules.databricks_private_subnet].network_security_group_id
    public_subnet_network_security_group_association_id  : data.azurerm_subnet.subnet[var.enabled_modules.databricks_public_subnet].network_security_group_id
    private_endpoint_subnet_name                         : var.enabled_modules.databricks_private_endpoint_subnet
    no_public_ip                                         : true
  }

  # Access connector enables Databricks Unity Catalog to authenticate to
  # Azure storage accounts without storing credentials in the workspace.
  access_connector = {
    name     : format("%s-connector", var.__ngc.environment_details.user_parameters.naming_service.analytics.databricks_workspace_name)
    identity : { type : "SystemAssigned" }
  }

  tags = local.tags
}

# Key Vault Secrets — Databricks
module "key_vault_secrets_databricks" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.databricks_workspace
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "WORKSPACE-URL" : {
      name            : "WORKSPACE-URL"
      # Workspace URL follows the platform naming convention:
      # <workspace_name>.azuredatabricksmanaged.rg
      value           : format("%s.azuredatabricksmanaged.rg", each.value.name)
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "WORKSPACE-ID" : {
      name            : "WORKSPACE-ID"
      value           : each.value.id
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# Outputs
output "outputs_databricks" {
  description = "Databricks Workspace outputs."
  value = {
    databricks_workspace : { for i, p in module.databricks_workspace : i => {
      id           : p.id
      name         : p.name
      workspace_id : p.workspace_id
      workspace_url : p.workspace_url
    }}
  }
}
