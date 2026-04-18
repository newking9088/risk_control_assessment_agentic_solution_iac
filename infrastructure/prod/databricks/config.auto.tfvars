# =============================================================================
# databricks/config.auto.tfvars — Prod Databricks sub-root configuration.
#
# Applied only when the databricks workflow variant is triggered:
#   terraform-plan-prod.yml  (input: databricks = true)
#   terraform-apply-prod.yml (input: databricks = true)
#
# IMPORTANT: Prod Databricks workspace is separate from non-prod.
# Do NOT reuse the same workspace_id / workspace_url as dev/qa/stage.
# Update these values manually with the prod workspace coordinates.
#
# Manual replacement (prod-specific — do NOT use the global replace script):
#   sed -i 's|__DATABRICKS_WORKSPACE_RESOURCE_ID__|<prod_arm_path>|g' \
#     infrastructure/prod/databricks/config.auto.tfvars
#   sed -i 's|__DATABRICKS_WORKSPACE_URL__|<prod_hostname>|g' \
#     infrastructure/prod/databricks/config.auto.tfvars
# =============================================================================

databricks = {
  workspace_id  : "__DATABRICKS_WORKSPACE_RESOURCE_ID__"
  workspace_url : "__DATABRICKS_WORKSPACE_URL__"

  users : {
    __DATABRICKS_ADMIN_KEY__ : {
      user_email : "__DATABRICKS_ADMIN_EMAIL__"
      user_key   : "__DATABRICKS_ADMIN_KEY__"
    }
  }
}
