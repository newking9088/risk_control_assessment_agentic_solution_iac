# log_analytics.tf — Log Analytics Workspace.
#
# This workspace is the single diagnostics sink for all other modules.
# Every diagnostic_settings_* module in this root references:
#   module.log_analytics_workspace["diag"].id
#
# Must be deployed before any module that has diagnostic_logging enabled,
# as those modules reference this workspace ID directly.
#
# Only deployed when: enabled_modules.diagnostic_logging = true
#
# Placeholders in this file:
#   platform      — Terraform Enterprise organization

# Log Analytics Workspace
module "log_analytics_workspace" {
  source  = "west.tfe.nginternal.com/platform/log-analytics-workspace/azurerm"
  version = "11.0.0-3-1.7"

  # Key "diag" is the stable reference used by all diagnostic_settings modules.
  for_each = var.enabled_modules.diagnostic_logging ? toset(["diag"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.monitoring.log_analytics_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # 10 GB daily cap prevents runaway log ingestion costs in lower environments.
  daily_quota_gb = 10

  # 180-day retention satisfies standard audit and compliance requirements.
  retention_in_days = 180

  tags = local.tags
}

# Outputs
output "outputs_log_analytics" {
  description = "Log Analytics Workspace outputs."
  value = {
    log_analytics_workspace : { for i, p in module.log_analytics_workspace : i => {
      id                  : p.id
      name                : p.name
      workspace_id        : p.workspace_id
      primary_shared_key  : p.primary_shared_key
    }}
  }
}
