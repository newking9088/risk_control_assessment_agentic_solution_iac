# redis.tf — Azure Cache for Redis (Standard SKU, SSL-only, private endpoint).
#
# No BYOK encryption on Redis — CMK is not supported for the Standard SKU.
# Network isolation is achieved via private endpoint + firewall rules.
#
# Dependency chain:
#   redis_cache
#     ├─► private_endpoints_redis
#     ├─► diagnostic_settings_redis  (requires diagnostic_logging = true)
#     └─► key_vault_secrets_redis
#
# Only deployed when: enabled_modules.redis_cache = true
# Private endpoint also requires: enabled_modules.redis_subnet (subnet key string)
#
# Placeholders in this file:
#   west.tfe.nginternal.com           — Terraform Enterprise registry hostname
#   platform                — Terraform Enterprise organization

# Redis Cache
module "redis_cache" {
  source  = "west.tfe.nginternal.com/platform/redis-cache/azurerm"
  version = "10.4.1-3-1.7"

  for_each = var.enabled_modules.redis_cache ? toset(["app_redis"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.cache.redis_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  capacity = 1
  sku_name = "Standard"

  # TLS 1.2 minimum; non-SSL port disabled for all traffic.
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  redis_version       = 6

  # Assign a deterministic private IP from the subnet (.6 offset from the base).
  # cidrhost resolves the static IP without hard-coding an address.
  subnet_id                    = data.azurerm_subnet.subnet[var.enabled_modules.redis_subnet].id
  private_static_ip_address    = cidrhost(data.azurerm_subnet.subnet[var.enabled_modules.redis_subnet].address_prefix, 6)

  # Firewall rules restrict Redis access to known IP ranges only.
  # Format: name => { start_ip, end_ip }
  redis_firewall_rules = {
    aks_nodes : {
      start_ip : "10.200.0.0"
      end_ip   : "10.200.255.255"
    }
    org_public : {
      start_ip : "155.201.0.0"
      end_ip   : "155.201.255.255"
    }
    org_internal : {
      start_ip : "10.225.0.0"
      end_ip   : "10.225.255.255"
    }
  }

  tags = local.tags
}

# Private Endpoint — Redis
module "private_endpoints_redis" {
  source  = "west.tfe.nginternal.com/platform/private-endpoint/azurerm"
  version = "5.1.1-3-1.7"

  for_each = module.redis_cache

  name                           = each.key
  location                       = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name            = data.azurerm_resource_group.app_env_resource_group.group_name
  subnet_id                      = data.azurerm_subnet.subnet[var.enabled_modules.redis_subnet].id
  private_connection_resource_id = each.value.id
  subresources                   = ["redisCache"]
  request_message                = "PL"
  tags                           = local.tags
}

# Diagnostic Settings — Redis
module "diagnostic_settings_redis" {
  source  = "west.tfe.nginternal.com/platform/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  for_each = var.enabled_modules.diagnostic_logging ? module.redis_cache : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "ConnectedClientList",         enabled : true },
    { category : "HSEntraAuthenticationAuditing", enabled : true },
  ]
}

# Key Vault Secrets — Redis
module "key_vault_secrets_redis" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.redis_cache
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "REDIS-HOST" : {
      name            : "REDIS-HOST"
      value           : each.value.hostname
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "REDIS-BUS-CONN-STRING" : {
      name            : "REDIS-BUS-CONN-STRING"
      value           : each.value.primary_connection_string
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "REDIS-ACCESS-KEY" : {
      name            : "REDIS-ACCESS-KEY"
      value           : each.value.primary_access_key
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# Outputs
output "outputs_redis" {
  description = "Redis Cache outputs."
  value = {
    redis_cache : { for i, p in module.redis_cache : i => {
      id       : p.id
      name     : p.name
      hostname : p.hostname
    }}
  }
}
