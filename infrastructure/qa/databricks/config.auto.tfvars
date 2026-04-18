# Edit this file to configure the Databricks workspace for this environment.
# workspace_id : Full ARM resource ID of the Databricks workspace.
# workspace_url: Hostname of the Databricks workspace (e.g. adb-1234567890.12.azuredatabricks.net).

databricks = {
  workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app-dev/providers/Microsoft.Databricks/workspaces/dbw-rca-dev"
  workspace_url = "adb-1234567890123456.1.azuredatabricks.net"
  users = {
    raj_paudel = {
      user_email = "raj.paudel@example.com"
      user_key   = "raj_paudel"
    }
  }
}
