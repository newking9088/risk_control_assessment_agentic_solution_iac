# =============================================================================
# databricks/config.auto.tfvars — Stage Databricks sub-root configuration.
#
# Applied only when the databricks workflow variant is triggered:
#   terraform-plan-stage.yml  (input: databricks = true)
#   terraform-apply-stage.yml (input: databricks = true)
#
# NOTE: If stage uses a different Databricks workspace than dev/qa, update
# workspace_id and workspace_url independently here.
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
