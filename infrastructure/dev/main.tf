# =============================================================================
# main.tf — Locals, resource group data source, and subnet lookups.
#
# This file wires the NGC platform context (__ngc) into usable locals
# that every other module in this root references.
# =============================================================================

# =============================================================================
# Locals
# =============================================================================
locals {
  # ── Tags ────────────────────────────────────────────────────────────────────
  # All tags flow from the NGC platform variable to satisfy compliance policy.
  # Never hard-code tag values here.
  tags = {
    ghs-log                : var.__ngc.environment_details.system_parameters.TAGS["ghs-log"]
    ghs-solution           : var.__ngc.environment_details.system_parameters.TAGS["ghs-solution"]
    ghs-appid              : var.__ngc.environment_details.system_parameters.TAGS["ghs-appid"]
    ghs-solutionexposure   : var.__ngc.environment_details.system_parameters.TAGS["ghs-solutionexposure"]
    ghs-serviceoffering    : var.__ngc.environment_details.system_parameters.TAGS["ghs-serviceoffering"]
    ghs-environment        : var.__ngc.environment_details.system_parameters.TAGS["ghs-environment"]
    ghs-owner              : var.__ngc.environment_details.system_parameters.TAGS["ghs-owner"]
    ghs-appfield           : var.__ngc.environment_details.system_parameters.TAGS["ghs-appfield"]
    ghs-envid              : var.__ngc.environment_details.system_parameters.TAGS["ghs-envid"]
    ghs-tariff             : var.__ngc.environment_details.system_parameters.TAGS["ghs-tariff"]
    ghs-grid               : var.__ngc.environment_details.system_parameters.TAGS["ghs-grid"]
    ghs-environmenttype    : var.__ngc.environment_details.system_parameters.TAGS["ghs-environmenttype"]
    ghs-deployedby         : var.__ngc.environment_details.system_parameters.TAGS["ghs-deployedby"]
    ghs-dataclassification : var.__ngc.environment_details.system_parameters.TAGS["ghs-dataclassification"]
  }

  # ── VNET Resource Group ──────────────────────────────────────────────────────
  # Platform convention: the VNET lives in a shared "AGP-BASE" resource group.
  # Derive it by replacing the "-INT-" segment in the environment RG name.
  vnet_resource_group_name = replace(
    var.__ngc.environment_details.user_parameters.naming_service.network.vnet_name,
    "-INT-",
    "-AGP-BASE-"
  )

  # ── Subnet Map ───────────────────────────────────────────────────────────────
  # __ngc.subnets is a list of colon-delimited "arm_id:subnet_name" strings.
  # Parse into name => id so modules can reference subnets by logical name:
  #   data.azurerm_subnet.subnet["my_subnet_name"].id
  subnets = {
    for entry in var.__ngc.subnets :
    split(":", entry)[1] => split(":", entry)[0]
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# The environment resource group that all resources in this root are deployed into.
data "azurerm_resource_group" "app_env_resource_group" {
  name = var.__ngc.environment_resource_groups
}

# Dynamic subnet lookup — one data source per subnet in __ngc.subnets.
# Subnets live in the shared VNET resource group, not the app RG.
data "azurerm_subnet" "subnet" {
  for_each             = local.subnets
  name                 = each.key
  virtual_network_name = var.__ngc.environment_details.user_parameters.naming_service.network.vnet_name
  resource_group_name  = local.vnet_resource_group_name
}
