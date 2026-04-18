# =============================================================================
# databricks/variables.tf — Variables for the Databricks sub-root.
#
# This is a separate Terraform root from the parent environment root.
# It requires a live Databricks workspace (deployed by the parent root)
# and is planned / applied independently via the databricks workflow variants:
#   terraform-plan-<env>.yml  (with databricks = true input)
#   terraform-apply-<env>.yml (with databricks = true input)
#
# The TFE workspace for this root has "1" appended to the parent workspace name
# (e.g. "app-dev" → "app-dev1") to keep state isolated.
# =============================================================================

# Platform-injected context — same variable as the parent root but only
# used here for provider authentication fallback if needed.
variable "__ngc" {
  type        = any
  description = "Platform-injected configuration (naming, tags, subnets, resource groups)."
}

# Databricks workspace connection details and user list.
# Set workspace_id and workspace_url in config.auto.tfvars once the
# workspace is provisioned by the parent root.
#
# Replace via:
#   sed -i 's|__DATABRICKS_WORKSPACE_RESOURCE_ID__|<arm_path>|g' config.auto.tfvars
#   sed -i 's|__DATABRICKS_WORKSPACE_URL__|<hostname>|g'           config.auto.tfvars
#   sed -i 's|__DATABRICKS_ADMIN_EMAIL__|admin@example.com|g'      config.auto.tfvars
#   sed -i 's|__DATABRICKS_ADMIN_KEY__|admin_user|g'               config.auto.tfvars
variable "databricks" {
  type = object({
    # Full ARM resource ID of the Databricks workspace.
    workspace_id  : optional(string)
    # Workspace host URL, e.g. adb-1234567890.12.azuredatabricks.net
    workspace_url : optional(string)
    # Map of logical_key => { user_email, user_key } for admin provisioning.
    users : map(object({
      user_email : optional(string)
      user_key   : optional(string)
    }))
  })
  default = {
    workspace_id  : null
    workspace_url : null
    users         : {}
  }
  description = "Databricks workspace coordinates and initial admin user list."
}
