# =============================================================================
# variables.tf — Input variable declarations for all modules in this root.
#
# Placeholder tokens (format: __PLACEHOLDER_NAME__) appear in the defaults
# of variables that carry object IDs / IPs. Replace by running:
#   bash scripts/replace_placeholders.sh
# =============================================================================

# Platform-injected context: naming service, tags, subnets, resource groups.
# Provided automatically by the NGC platform at plan/apply time.
# Never set this manually in config.auto.tfvars.
variable "__ngc" {
  type        = any
  description = "Platform-injected configuration (naming, tags, subnets, resource groups)."
}

variable "database_name" {
  type        = string
  default     = "appdb"
  description = "Name of the PostgreSQL application database."
}

# Map of logical_name => azure_ad_object_id.
# Each entry produces one access policy on the application Key Vault.
# sed replacement:
#   sed -i 's|__KEYVAULT_ADMIN_1_NAME__|john_doe|g'        config.auto.tfvars
#   sed -i 's|__KEYVAULT_ADMIN_1_OBJECT_ID__|<uuid>|g'     config.auto.tfvars
variable "keyvault_admins_app" {
  type        = map(string)
  default     = {}
  description = "Admin name => Azure AD object ID for application Key Vault access policies."
}

# Map of logical_name => azure_ad_object_id for BYOK Key Vault admins.
variable "keyvault_admins_byok" {
  type        = map(string)
  default     = {}
  description = "Admin name => Azure AD object ID for BYOK Key Vault access policies."
}

# Full ARM subnet path used in Key Vault network ACLs and private endpoint rules.
# sed replacement:
#   sed -i 's|__NONPROD_AKS_SUBNET_ID__|/subscriptions/.../subnets/aks|g' config.auto.tfvars
variable "aks_subnet_id" {
  type        = string
  description = "Full ARM resource ID of the AKS subnet."
}

# Principals granted Storage Blob Data Contributor on the storage account.
# Default is populated from the platform admins group object ID.
variable "platform_admins" {
  type        = map(string)
  default     = { platform_admins : "__PLATFORM_ADMINS_OBJECT_ID__" }
  description = "Principal name => Azure AD object ID for blob contributor access."
}

# Synapse Analytics role assignments.
# Default grants Synapse Administrator to the platform admins group.
variable "synapse_users" {
  type = map(object({
    role_name    : string
    principal_id : string
  }))
  default = {
    admin : {
      role_name    : "Synapse Administrator"
      principal_id : "__PLATFORM_ADMINS_OBJECT_ID__"
    }
  }
  description = "Synapse role assignments: logical_name => { role_name, principal_id }."
}

# =============================================================================
# Feature Switches
# =============================================================================
# Every optional module is gated by a flag in this object.
# Key Vault is MANDATORY and is not controlled here.
# Set desired flags to true in config.auto.tfvars before running terraform plan.
variable "enabled_modules" {
  type = object({
    # Customer-managed key (CMK) vault. Must be true before enabling any
    # resource that uses CMK (storage, postgres, service_bus, cognitive, data_factory).
    byok : optional(bool, false)

    # Log Analytics workspace + diagnostic settings on all supporting resources.
    diagnostic_logging : optional(bool, false)

    # Azure Storage Account (HNS enabled, CMK via BYOK vault).
    storage_account : optional(bool, false)

    # Azure Cache for Redis (Premium, SSL-only).
    redis_cache  : optional(bool, false)
    # Subnet key from __ngc.subnets for the Redis private endpoint.
    redis_subnet : optional(string)

    # Azure Cognitive Services — Form Recognizer (S0 SKU).
    cognitive_account  : optional(bool, false)
    # Subnet key from __ngc.subnets for the Cognitive Services private endpoint.
    cognitive_subnet   : optional(string)

    # Azure Service Bus namespace (Premium SKU, zone-redundant, CMK).
    service_bus : optional(bool, false)

    # Azure Cognitive Search (Standard SKU).
    search_service : optional(bool, false)

    # Azure PostgreSQL Flexible Server (v16, GP_Standard_D2ds_v5, CMK).
    postgres        : optional(bool, false)
    # Subnet key from __ngc.subnets for the PostgreSQL private endpoint.
    postgres_subnet : optional(string)

    # Azure Databricks Workspace (infrastructure encryption + CMK).
    databricks                         : optional(bool, false)
    databricks_private_subnet          : optional(string)
    databricks_public_subnet           : optional(string)
    databricks_private_endpoint_subnet : optional(string)

    # Azure Data Factory (CMK, managed private endpoint to PostgreSQL when both enabled).
    data_factory        : optional(bool, false)
    # Subnet key from __ngc.subnets for the Data Factory managed private endpoint.
    data_factory_subnet : optional(string)

    # Azure Synapse Analytics workspace + SQL pool + Spark pool.
    synapse : optional(bool, false)
  })
  description = "Feature switches that control which optional modules are deployed."
}
