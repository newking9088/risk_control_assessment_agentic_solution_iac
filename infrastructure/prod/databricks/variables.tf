variable "__ngc" {
  type        = any
  description = "Platform-injected configuration (naming, tags, subnets, resource groups)."
}

variable "databricks" {
  type = object({
    workspace_id  = optional(string)
    workspace_url = optional(string)
    users = map(object({
      user_email = optional(string)
      user_key   = optional(string)
    }))
  })
  default = {
    workspace_id  = null
    workspace_url = null
    users         = {}
  }
  description = "Databricks workspace coordinates and initial admin user list."
}
