# =============================================================================
# databricks/admin.tf — Databricks user management (separate Terraform root).
#
# This root uses the databricks/databricks provider, not azurerm.
# Authentication is via the workspace resource ID and URL — no PAT required.
#
# What this root does:
#   1. Looks up the built-in "admins" group in the workspace.
#   2. Creates a Databricks user for each entry in var.databricks.users.
#   3. Adds every created user to the admins group.
#
# Run order relative to the parent root:
#   Parent root apply  →  this root apply
#   (workspace must exist before users can be provisioned)
#
# Placeholders in this file:
#   __TFE_HOSTNAME__ — Terraform Enterprise registry hostname
#   __TFE_ORG__      — Terraform Enterprise organization
# =============================================================================

# =============================================================================
# Provider Configuration
# =============================================================================
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1"
    }
  }
}

provider "databricks" {
  # Authenticate using the workspace ARM resource ID and host URL.
  # Credentials are resolved from the Azure CLI / service principal context
  # available to the GitHub Actions runner at apply time.
  azure_resource_id = var.databricks.workspace_id
  host              = format("https://%s", var.databricks.workspace_url)
}

# =============================================================================
# Admins Group Lookup
# =============================================================================
# The "admins" group is created automatically by Databricks on workspace init.
# We look it up rather than creating it so we never accidentally recreate it.
data "databricks_group" "admins" {
  display_name = "admins"
}

# =============================================================================
# Databricks Users
# =============================================================================
# Creates one Databricks user per entry in var.databricks.users.
# The user_key is the logical map key; user_email is the identity used for login.
module "databricks_users" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/group-member/databricks"
  version = "4.0.0-3-1.3"

  # Iterate every user defined in config.auto.tfvars.
  for_each = var.databricks.users

  group_id  = data.databricks_group.admins.id
  user_name = each.value.user_email
}
