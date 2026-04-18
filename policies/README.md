# Policies

Enforcement surfaces are scaffolded here. Follow-up PRs will add the final
policy set once the platform team completes the Sentinel configuration.

## Sentinel (Terraform Enterprise)

`policies/sentinel/*.sentinel` files run inside Terraform Enterprise on every
plan before apply. Policies apply in this repo only.

Reference: https://developer.hashicorp.com/sentinel/docs/concepts/terraform

## OPA (Open Policy Agent)

`policies/opa/restrict.rego` flags policies enforced outside the TFE element.
Add a top-level comment in each `.rego` file explaining why.

## Minimum Baseline Policies Enforced

| Policy | Rule |
|--------|------|
| `keyvault-purge-protection` | Every Key Vault must have `purge_protection_enabled = true` and `default_action = "Deny"` |
| `storage-no-public-access` | `public_network_access_enabled = false` on every Storage Account |
| `no-open-firewall-rules` | No `0.0.0.0/0` in any `firewall_rules` block |
| `required-tags` | Every resource inherits the full `local.tags` map |

## Status

This directory ships as a scaffold only. Follow-up PRs will add the final
policy set once the platform team completes the Sentinel configuration.
