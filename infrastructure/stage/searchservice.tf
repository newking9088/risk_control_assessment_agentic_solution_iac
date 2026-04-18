# searchservice.tf — Azure Cognitive Search (Standard SKU).
#
# No BYOK, no private endpoint, no diagnostic settings for this module.
# Network access is restricted to the org public IP CIDR via allowed IPs.
#
# Dependency chain:
#   search_service
#     └─► key_vault_secrets_search
#
# Only deployed when: enabled_modules.search_service = true
#
# Placeholders in this file:
#   platform            — Terraform Enterprise organization

# Cognitive Search Service
module "search_service" {
  source  = "west.tfe.nginternal.com/platform/searchservice/azurerm"
  version = "10.1.1-3-1.7"

  for_each = var.enabled_modules.search_service ? toset(["app_search"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.search.search_service_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  sku            = "standard"
  replica_count  = 1
  partition_count = 1

  # Restrict inbound access to org egress IPs only.
  allowed_ips = var.org_public_ip_cidrs

  tags = local.tags
}

# Key Vault Secrets — Cognitive Search
module "key_vault_secrets_search" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.search_service
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "SEARCH-NAME" : {
      name            : "SEARCH-NAME"
      value           : each.value.name
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "SEARCH-PRIMARY-KEY" : {
      name            : "SEARCH-PRIMARY-KEY"
      value           : each.value.primary_key
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# Outputs
output "outputs_search_service" {
  description = "Cognitive Search Service outputs."
  value = {
    search_service : { for i, p in module.search_service : i => {
      id   : p.id
      name : p.name
    }}
  }
}
