# servicebus.tf — Azure Service Bus namespace (Premium SKU, zone-redundant, CMK).
#
# BYOK dependency chain (Section 3.5):
#   user_assigned_identity_service_bus
#     └─► access_policies_byok_service_bus  (grants WrapKey / UnwrapKey to identity)
#           └─► time_sleep_service_bus      (30 s — policy propagation)
#                 └─► service_bus           (CMK + infrastructure encryption)
#                       ├─► service_bus_queues
#                       ├─► diagnostic_settings_service_bus  (diagnostic_logging)
#                       └─► key_vault_secrets_service_bus
#
# Only deployed when: enabled_modules.service_bus = true
#
# Placeholders in this file:
#   platform            — Terraform Enterprise organization

# User-Assigned Managed Identity — Service Bus
module "user_assigned_identity_service_bus" {
  source  = "west.tfe.nginternal.com/platform/user-assigned-identity/azurerm"
  version = "4.1.0-3-1.7"

  for_each = var.enabled_modules.service_bus ? toset(["service_bus"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.identity.service_bus_identity_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tags                = local.tags
}

# BYOK Access Policy — Service Bus Identity
module "access_policies_byok_service_bus" {
  source  = "west.tfe.nginternal.com/platform/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  for_each = {
    for pair in setproduct(keys(module.user_assigned_identity_service_bus), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      identity_key : pair[0]
      vault_key    : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = module.user_assigned_identity_service_bus[each.value.identity_key].principal_id

  key_permissions         : ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions      : []
  certificate_permissions : []
}

# Time Sleep — Service Bus
module "time_sleep_service_bus" {
  source  = "west.tfe.nginternal.com/platform/time-sleep/time"
  version = "2.0.0-3-1.7"

  for_each        = var.enabled_modules.service_bus ? toset(["service_bus"]) : toset([])
  create_duration = "30s"

  depends_on = [module.access_policies_byok_service_bus]
}

# Service Bus Namespace
module "service_bus" {
  source  = "west.tfe.nginternal.com/platform/servicebus-namespace/azurerm"
  version = "12.0.0-3-1.7"

  for_each = var.enabled_modules.service_bus ? toset(["app_service_bus"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.messaging.service_bus_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  # Premium SKU is required for VNet integration, zone redundancy, and CMK.
  sku      = "Premium"
  capacity = 1

  # Zone redundancy spreads the namespace across availability zones.
  zone_redundant = true

  # Premium messaging units; 1 unit is sufficient for most workloads.
  premium_messaging_partitions = 1

  # Public network access is left enabled so Azure-internal services can reach
  # the namespace. Network rule default_action=Deny with trusted services allowed
  # prevents external access while allowing Azure service bus connectors.
  public_network_access_enabled = true

  network_rule_set = {
    default_action                : "Deny"
    trusted_services_allowed      : true
    ip_rules                      : var.org_public_ip_cidrs
  }

  # Infrastructure encryption provides a second layer of encryption at rest
  # in addition to the CMK envelope encryption.
  infrastructure_encryption_enabled = true

  # CMK encryption via BYOK vault.
  customer_managed_key = var.enabled_modules.byok ? {
    key_vault_key_id          : module.keyvault_byok["byok_keyvault"].cognitive_key_id
    identity_client_id        : module.user_assigned_identity_service_bus["service_bus"].client_id
  } : null

  identity = var.enabled_modules.byok ? {
    type         : "UserAssigned"
    identity_ids : [module.user_assigned_identity_service_bus["service_bus"].id]
  } : null

  tags = local.tags

  depends_on = [module.time_sleep_service_bus]
}

# Service Bus Queues
module "service_bus_queues" {
  source  = "west.tfe.nginternal.com/platform/servicebus-queue/azurerm"
  version = "10.0.0-3-1.7"

  for_each = module.service_bus

  namespace_id = each.value.id
  name         = var.__ngc.environment_details.user_parameters.naming_service.messaging.service_bus_queue_name

  # Message lock duration prevents a consumer from holding a message indefinitely.
  lock_duration = "PT1M"

  # Messages that are not consumed within 1 day are dead-lettered.
  default_message_ttl = "P1D"

  # Duplicate detection window matches the lock duration window.
  requires_duplicate_detection          = true
  duplicate_detection_history_time_window = "PT1M"

  # Batched operations improve throughput for high-volume queue consumers.
  enable_batched_operations = true
}

# Diagnostic Settings — Service Bus
module "diagnostic_settings_service_bus" {
  source  = "west.tfe.nginternal.com/platform/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  for_each = var.enabled_modules.diagnostic_logging ? module.service_bus : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "ApplicationMetrics",          enabled : true },
    { category : "DiagnosticErrorLogs",          enabled : true },
    { category : "OperationalLogs",              enabled : true },
    { category : "RuntimeAuditLogs",             enabled : true },
    { category : "VNetAndIPFilteringLogs",        enabled : true },
  ]
}

# Key Vault Secrets — Service Bus
module "key_vault_secrets_service_bus" {
  source  = "west.tfe.nginternal.com/platform/key-vault-secret/azurerm"
  version = "5.0.0-3-1.7"

  for_each     = module.service_bus
  key_vault_id = module.keyvault["app_keyvault"].id

  secrets = {
    "SERVICEBUS-NAME" : {
      name            : "SERVICEBUS-NAME"
      value           : each.value.name
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
    "SERVICEBUS-DEFAULT-PRIMARY-CONNECTION-STRING" : {
      name            : "SERVICEBUS-DEFAULT-PRIMARY-CONNECTION-STRING"
      value           : each.value.default_primary_connection_string
      content_type    : null
      not_before_date : null
      expiration_date : null
      tags            : {}
    }
  }
}

# Outputs
output "outputs_service_bus" {
  description = "Service Bus outputs."
  value = {
    service_bus : { for i, p in module.service_bus : i => {
      id   : p.id
      name : p.name
    }}
  }
}
