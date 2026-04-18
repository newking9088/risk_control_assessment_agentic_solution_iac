# =============================================================================
# cognitive.tf — Azure Cognitive Services (Form Recognizer, S0 SKU).
#
# BYOK dependency chain (Section 3.5):
#   user_assigned_identity_cognitive
#     └─► access_policies_byok_cognitive  (grants WrapKey / UnwrapKey to identity)
#           └─► time_sleep_cognitive      (30 s — policy propagation)
#                 └─► cognitive_account   (CMK references identity + BYOK key)
#                       ├─► diagnostic_settings_cognitive  (diagnostic_logging)
#                       └─► private_endpoint_cognitive
#
# Only deployed when: enabled_modules.cognitive_account = true
# Private endpoint also requires: enabled_modules.cognitive_subnet (subnet key string)
#
# Placeholders in this file:
#   __TFE_HOSTNAME__       — Terraform Enterprise registry hostname
#   __TFE_ORG__            — Terraform Enterprise organization
#   __ORG_PUBLIC_IP_CIDR__ — Org egress CIDR, e.g. 203.0.113.0/24
# =============================================================================

# =============================================================================
# User-Assigned Managed Identity — Cognitive Services
# =============================================================================
module "user_assigned_identity_cognitive" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/user-assigned-identity/azurerm"
  version = "4.1.0-3-1.7"

  for_each = var.enabled_modules.cognitive_account ? toset(["cognitive"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.identity.cognitive_identity_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name
  tags                = local.tags
}

# =============================================================================
# BYOK Access Policy — Cognitive Identity
# =============================================================================
module "access_policies_byok_cognitive" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/keyvault-access-policy/azurerm"
  version = "12.0.0-3-1.7"

  for_each = {
    for pair in setproduct(keys(module.user_assigned_identity_cognitive), keys(module.keyvault_byok)) :
    format("%s_%s", pair[0], pair[1]) => {
      identity_key : pair[0]
      vault_key    : pair[1]
    }
  }

  key_vault_id = module.keyvault_byok[each.value.vault_key].id
  tenant_id    = var.__ngc.environment_details.system_parameters.TENANT_ID
  object_id    = module.user_assigned_identity_cognitive[each.value.identity_key].principal_id

  key_permissions         : ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions      : []
  certificate_permissions : []
}

# =============================================================================
# Time Sleep — Cognitive Services
# =============================================================================
# Azure AD policy replication latency: wait 30 s before creating the
# Cognitive account so the identity can access the BYOK key on first use.
module "time_sleep_cognitive" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/time-sleep/time"
  version = "2.0.0-3-1.7"

  for_each        = var.enabled_modules.cognitive_account ? toset(["cognitive"]) : toset([])
  create_duration = "30s"

  depends_on = [module.access_policies_byok_cognitive]
}

# =============================================================================
# Cognitive Services Account — Form Recognizer
# =============================================================================
module "cognitive_account" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/cognitive-account/azurerm"
  version = "10.2.0-3-1.7"

  for_each = var.enabled_modules.cognitive_account ? toset(["form_recognizer"]) : toset([])

  name                = var.__ngc.environment_details.user_parameters.naming_service.ai.cognitive_account_name
  location            = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name = data.azurerm_resource_group.app_env_resource_group.name

  kind     = "FormRecognizer"
  sku_name = "S0"

  # Public network access must remain enabled for the private endpoint to register.
  # Azure requires the resource to be reachable during PE provisioning.
  public_network_access_enabled = true

  # Network ACLs restrict which IPs and subnets can reach the public endpoint.
  network_acls = {
    default_action : "Deny"
    ip_rules       : ["__ORG_PUBLIC_IP_CIDR__"]
    virtual_network_rules : [
      { subnet_id : data.azurerm_subnet.subnet[var.enabled_modules.cognitive_subnet].id },
      { subnet_id : var.aks_subnet_id },
    ]
  }

  # UserAssigned identity is required to use a customer-managed key.
  identity = {
    type         : "UserAssigned"
    identity_ids : [module.user_assigned_identity_cognitive["cognitive"].id]
  }

  # CMK encryption via BYOK vault — only wired when byok is enabled.
  customer_managed_key = var.enabled_modules.byok ? {
    key_vault_key_id          : module.keyvault_byok["byok_keyvault"].cognitive_key_id
    identity_client_id        : module.user_assigned_identity_cognitive["cognitive"].client_id
  } : null

  tags = local.tags

  depends_on = [module.time_sleep_cognitive]
}

# =============================================================================
# Diagnostic Settings — Cognitive Services
# =============================================================================
module "diagnostic_settings_cognitive" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/monitor-diagnostic-setting/azurerm"
  version = "4.1.1-3-1.7"

  for_each = var.enabled_modules.diagnostic_logging ? module.cognitive_account : {}

  name                       = format("m-diag-%s", each.value.name)
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace["diag"].id

  enabled_log = [
    { category : "Audit",                   enabled : true },
    { category : "AzureOpenAIRequestImage",  enabled : true },
  ]
}

# =============================================================================
# Private Endpoint — Cognitive Services
# =============================================================================
module "private_endpoint_cognitive" {
  source  = "__TFE_HOSTNAME__/__TFE_ORG__/private-endpoint/azurerm"
  version = "5.1.1-3-1.7"

  for_each = module.cognitive_account

  name                           = each.key
  location                       = data.azurerm_resource_group.app_env_resource_group.location
  resource_group_name            = data.azurerm_resource_group.app_env_resource_group.group_name
  subnet_id                      = data.azurerm_subnet.subnet[var.enabled_modules.cognitive_subnet].id
  private_connection_resource_id = each.value.id
  subresources                   = ["account"]
  request_message                = "PL"
  tags                           = local.tags
}

# =============================================================================
# Outputs
# =============================================================================
output "outputs_cognitive" {
  description = "Cognitive Services outputs."
  value = {
    cognitive_account : { for i, p in module.cognitive_account : i => {
      id       : p.id
      name     : p.name
      endpoint : p.endpoint
    }}
  }
}
