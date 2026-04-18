variable "__ngc" {
  type        = any
  description = "Platform-injected configuration (naming, tags, subnets, resource groups)."
}

variable "database_name" {
  type        = string
  default     = "appdb"
  description = "Name of the PostgreSQL application database."
}

variable "keyvault_admins_app" {
  type        = map(string)
  default     = {}
  description = "Admin name => Azure AD object ID for application Key Vault access policies."
}

variable "keyvault_admins_byok" {
  type        = map(string)
  default     = {}
  description = "Admin name => Azure AD object ID for BYOK Key Vault access policies."
}

variable "aks_subnet_id" {
  type        = string
  description = "Full ARM resource ID of the AKS subnet."
}

variable "spn_object_id" {
  type        = string
  description = "Azure AD object ID of the deployment service principal."
}

variable "aks_spn_object_id" {
  type        = string
  description = "Azure AD object ID of the AKS cluster service principal."
}

variable "org_public_ip_cidrs" {
  type        = list(string)
  description = "List of org egress CIDRs allowed through resource firewall rules."
}

variable "platform_admins" {
  type        = map(string)
  default     = {}
  description = "Principal name => Azure AD object ID for blob contributor access."
}

variable "synapse_users" {
  type = map(object({
    role_name    = string
    principal_id = string
  }))
  default     = {}
  description = "Synapse role assignments: logical_name => { role_name, principal_id }."
}

variable "enabled_modules" {
  type = object({
    byok               = optional(bool, false)
    diagnostic_logging = optional(bool, false)
    storage_account    = optional(bool, false)
    redis_cache        = optional(bool, false)
    redis_subnet       = optional(string)
    cognitive_account  = optional(bool, false)
    cognitive_subnet   = optional(string)
    service_bus        = optional(bool, false)
    search_service     = optional(bool, false)
    postgres           = optional(bool, false)
    postgres_subnet    = optional(string)
    databricks                         = optional(bool, false)
    databricks_private_subnet          = optional(string)
    databricks_public_subnet           = optional(string)
    databricks_private_endpoint_subnet = optional(string)
    data_factory        = optional(bool, false)
    data_factory_subnet = optional(string)
    synapse             = optional(bool, false)
  })
  description = "Feature switches that control which optional modules are deployed."
}
