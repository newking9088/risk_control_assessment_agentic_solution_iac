# =============================================================================
# databricks/config.auto.tfvars — Dev Databricks sub-root configuration.
#
# Applied only when the databricks workflow variant is triggered:
#   terraform-plan-dev.yml  (input: databricks = true)
#   terraform-apply-dev.yml (input: databricks = true)
#
# The workspace_id and workspace_url must be populated after the parent
# root has been applied and the Databricks workspace is live.
#
# NOTE: Each environment has its own Databricks workspace — update workspace_id
# and workspace_url independently per env; do NOT use the global replace script
# for these values if environments use different workspaces.
#
# Placeholder replacement (single file):
#   sed -i 's|__DATABRICKS_WORKSPACE_RESOURCE_ID__|<arm_path>|g' \
#     infrastructure/dev/databricks/config.auto.tfvars
#   sed -i 's|__DATABRICKS_WORKSPACE_URL__|<hostname>|g' \
#     infrastructure/dev/databricks/config.auto.tfvars
#   sed -i 's|__DATABRICKS_ADMIN_EMAIL__|admin@example.com|g' \
#     infrastructure/dev/databricks/config.auto.tfvars
#   sed -i 's|__DATABRICKS_ADMIN_KEY__|admin_user|g' \
#     infrastructure/dev/databricks/config.auto.tfvars
# =============================================================================

databricks = {
  # Full ARM resource ID of the dev Databricks workspace.
  # /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Databricks/workspaces/<name>
  workspace_id : "__DATABRICKS_WORKSPACE_RESOURCE_ID__"

  # Workspace host URL without https://, e.g. adb-1234567890.12.azuredatabricks.net
  workspace_url : "__DATABRICKS_WORKSPACE_URL__"

  # Initial admin users to provision in the workspace admins group.
  # Add further entries using the same pattern: logical_key => { user_email, user_key }
  users : {
    __DATABRICKS_ADMIN_KEY__ : {
      user_email : "__DATABRICKS_ADMIN_EMAIL__"
      user_key   : "__DATABRICKS_ADMIN_KEY__"
    }
  }
}
