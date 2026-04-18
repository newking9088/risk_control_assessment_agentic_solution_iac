# =============================================================================
# config.auto.tfvars — Stage environment configuration.
#
# This is the ONLY file that differs between dev / qa / stage / prod.
# All .tf files in this directory are identical across environments.
#
# Stage shares the non-prod Azure subscription with dev and qa.
# Stage is the final validation gate before production — consider enabling
# all modules here that are enabled in prod to catch issues pre-release.
#
# Placeholder replacement (run from repo root after filling placeholders.env):
#   bash scripts/replace_placeholders.sh
#
# Manual single-value replacement:
#   sed -i 's|__NONPROD_AKS_SUBNET_ID__|/subscriptions/.../subnets/aks|g' \
#     infrastructure/stage/config.auto.tfvars
# =============================================================================

database_name = "appdb"

# =============================================================================
# Feature Switches
# =============================================================================
enabled_modules = {
  byok               : false
  diagnostic_logging : false

  storage_account : false

  redis_cache  : false
  # Subnet key string from __ngc.subnets — required when redis_cache = true.
  # Example: "redis-subnet"
  redis_subnet : null

  cognitive_account : false
  # Subnet key string from __ngc.subnets — required when cognitive_account = true.
  cognitive_subnet  : null

  service_bus    : false
  search_service : false

  postgres        : false
  # Subnet key string from __ngc.subnets — required when postgres = true.
  postgres_subnet : null

  databricks                         : false
  databricks_private_subnet          : null
  databricks_public_subnet           : null
  databricks_private_endpoint_subnet : null

  data_factory        : false
  # Subnet key string from __ngc.subnets — required when data_factory = true.
  data_factory_subnet : null

  synapse : false
}

# =============================================================================
# Key Vault Admins
# =============================================================================
keyvault_admins_app = {
  __KEYVAULT_ADMIN_1_NAME__ : "__KEYVAULT_ADMIN_1_OBJECT_ID__"
  __KEYVAULT_ADMIN_2_NAME__ : "__KEYVAULT_ADMIN_2_OBJECT_ID__"
}

keyvault_admins_byok = {
  __KEYVAULT_ADMIN_1_NAME__ : "__KEYVAULT_ADMIN_1_OBJECT_ID__"
  __KEYVAULT_ADMIN_2_NAME__ : "__KEYVAULT_ADMIN_2_OBJECT_ID__"
}

# =============================================================================
# Networking
# =============================================================================
# Non-prod AKS subnet — shared by dev, qa, and stage.
aks_subnet_id = "__NONPROD_AKS_SUBNET_ID__"

# =============================================================================
# Optional Overrides
# =============================================================================
# platform_admins = {
#   platform_admins : "__PLATFORM_ADMINS_OBJECT_ID__"
# }

# synapse_users = {
#   admin : {
#     role_name    : "Synapse Administrator"
#     principal_id : "__PLATFORM_ADMINS_OBJECT_ID__"
#   }
# }
