# Base Infrastructure Template

Modular Azure Infrastructure-as-Code using Terraform Enterprise modules. Every optional resource is gated by a feature switch — Key Vault is the only mandatory resource. All other modules are enabled per environment via `config.auto.tfvars`.

---

## Architecture Overview

```
infrastructure/
  dev/    ─┐
  qa/      ├─ Identical .tf files. Only config.auto.tfvars differs.
  stage/   │
  prod/   ─┘
    ├── provider.tf          — AzureRM provider
    ├── variables.tf         — All input variables + enabled_modules object
    ├── main.tf              — Locals (tags, subnets), data sources
    ├── keyvault.tf          — MANDATORY: app Key Vault + admin policies + diagnostics
    ├── keyvault_byok.tf     — BYOK vault for customer-managed keys
    ├── storage.tf           — Storage Account (HNS, GRS, CMK)
    ├── redis.tf             — Redis Cache (Standard, SSL-only)
    ├── postgres.tf          — PostgreSQL Flexible Server (v16, CMK)
    ├── cognitive.tf         — Cognitive Services / Form Recognizer (CMK)
    ├── servicebus.tf        — Service Bus (Premium, zone-redundant, CMK)
    ├── searchservice.tf     — Cognitive Search (Standard)
    ├── databricks.tf        — Databricks Workspace (infra encryption, CMK)
    ├── data_factory.tf      — Data Factory (CMK, managed PE to Postgres)
    ├── synapse.tf           — Synapse Analytics (SQL pool + Spark pool)
    ├── log_analytics.tf     — Log Analytics Workspace (diagnostics sink)
    ├── vcluster.yaml        — vCluster configuration (k3s, ingress sync)
    └── databricks/
        ├── admin.tf         — Databricks user management (separate TF root)
        ├── variables.tf
        └── config.auto.tfvars
```

---

## Core Components

### Mandatory
| Module | File | Notes |
|--------|------|-------|
| Application Key Vault | `keyvault.tf` | Always deployed. Stores all secrets from other modules. |

### Optional (controlled by `enabled_modules`)
| Module | File | Feature Flag |
|--------|------|-------------|
| BYOK Key Vault | `keyvault_byok.tf` | `byok` — required before enabling any CMK-backed resource |
| Log Analytics | `log_analytics.tf` | `diagnostic_logging` — required before enabling any diagnostics |
| Storage Account | `storage.tf` | `storage_account` |
| Redis Cache | `redis.tf` | `redis_cache` |
| PostgreSQL Flexible Server | `postgres.tf` | `postgres` |
| Cognitive Services | `cognitive.tf` | `cognitive_account` |
| Service Bus | `servicebus.tf` | `service_bus` |
| Cognitive Search | `searchservice.tf` | `search_service` |
| Databricks Workspace | `databricks.tf` | `databricks` |
| Data Factory | `data_factory.tf` | `data_factory` |
| Synapse Analytics | `synapse.tf` | `synapse` |

---

## Configuration

### Enabling Modules

All flags default to `false`. Edit `infrastructure/<env>/config.auto.tfvars`:

```hcl
enabled_modules = {
  byok               : true   # enable first
  diagnostic_logging : true   # enable second
  storage_account    : true   # then individual resources
  postgres           : true
  postgres_subnet    : "my-postgres-subnet-name"
  # ... all others remain false
}
```

**Order matters for CMK resources:** `byok` must be `true` before enabling `storage_account`, `postgres`, `service_bus`, `cognitive_account`, or `data_factory`.

### Subnet Keys

Subnet values (`redis_subnet`, `postgres_subnet`, etc.) are the **name portion** of the colon-delimited entries in `var.__ngc.subnets`, not ARM paths. The `main.tf` locals block parses `"arm_id:subnet_name"` strings into a lookup map.

---

## Module Patterns

### Feature Switch (`for_each` ternary)

Every optional module uses this pattern — enabled produces one instance, disabled produces nothing:

```hcl
module "redis_cache" {
  source   = "__TFE_HOSTNAME__/__TFE_ORG__/redis-cache/azurerm"
  version  = "10.4.1-3-1.7"
  for_each = var.enabled_modules.redis_cache ? toset(["app_redis"]) : toset([])
  # ...
}
```

For modules with richer config:

```hcl
module "storage_accounts" {
  source   = "__TFE_HOSTNAME__/__TFE_ORG__/storage-account/azurerm"
  version  = "15.4.2-3-1.7"
  for_each = var.enabled_modules.storage_account ? {
    app_storage : { name : var.__ngc.environment_details.user_parameters.naming_service.storage.storage_account_name }
  } : {}
  # ...
}
```

### BYOK Encryption Chain

Every CMK-backed resource follows this four-step dependency chain:

```
user_assigned_identity
  └─► access_policies_byok   (grants WrapKey / UnwrapKey)
        └─► time_sleep        (30 s — policy propagation)
              └─► resource    (customer_managed_key block)
```

### Secrets Storage

Every module writes its connection strings to the app Key Vault after creation:

```hcl
module "key_vault_secrets_redis" {
  source       = "__TFE_HOSTNAME__/__TFE_ORG__/key-vault-secret/azurerm"
  version      = "5.0.0-3-1.7"
  for_each     = module.redis_cache
  key_vault_id = module.keyvault["app_keyvault"].id
  secrets = {
    "REDIS-HOST" : { name : "REDIS-HOST", value : each.value.hostname, ... }
  }
}
```

---

## Deployments

### Standard (PR + apply)

1. Open PR targeting `main` — plan workflow triggers automatically for the affected environment.
2. Review the plan output in the PR checks.
3. Merge the PR.
4. Trigger `terraform-apply-<env>.yml` manually via GitHub Actions → `workflow_dispatch`.

### Databricks Sub-Root

The `databricks/` directory is a separate Terraform root with its own TFE workspace (name suffix `1`).

1. Ensure the parent root has been applied and the workspace exists.
2. Fill in `databricks/config.auto.tfvars` with the workspace ID and URL.
3. Trigger the plan or apply workflow with **`databricks` input = `true`**.

---

## Adding a New Module

1. Add a feature flag to the `enabled_modules` object in `variables.tf`:
   ```hcl
   my_new_resource : optional(bool, false)
   ```
2. Default it to `false` in `config.auto.tfvars` for all four environments.
3. Create `my_new_resource.tf` in `infrastructure/dev/` following the `for_each` ternary pattern.
4. Copy the file to `qa/`, `stage/`, and `prod/` — the `.tf` files are always identical.
5. Set the flag to `true` in the target environment's `config.auto.tfvars` to enable it.

---

## Key Vault Administration

Two separate Key Vault instances can be deployed:

| Vault | Variable | Purpose |
|-------|----------|---------|
| App Key Vault | `keyvault_admins_app` | Stores all application secrets (connection strings, keys, endpoints) |
| BYOK Key Vault | `keyvault_admins_byok` | Holds customer-managed encryption keys — only when `byok = true` |

Admins are configured as a `map(string)` of `logical_name => azure_ad_object_id` in `config.auto.tfvars`. Each entry produces one access policy resource:

```hcl
keyvault_admins_app = {
  john_doe  : "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  jane_smith : "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
}
```

---

## Diagnostic Logging

When `diagnostic_logging = true`, a Log Analytics Workspace is deployed and every module that supports diagnostics attaches a `diagnostic_settings_*` companion module targeting `module.log_analytics_workspace["diag"].id`.

| Resource | Log Categories |
|----------|---------------|
| Key Vaults | `AuditEvent`, `AzurePolicyEvaluationDetails` |
| Redis | `ConnectedClientList`, `HSEntraAuthenticationAuditing` |
| PostgreSQL | `PostgreSQLLogs`, `PostgreSQLFlexSessions` |
| Service Bus | `ApplicationMetrics`, `DiagnosticErrorLogs`, `OperationalLogs`, `RuntimeAuditLogs`, `VNetAndIPFilteringLogs` |
| Cognitive Services | `Audit`, `AzureOpenAIRequestImage` |
| Storage | `StorageRead`, `StorageWrite`, `StorageDelete` — applied per sub-service (`blobServices`, `queueServices`, `tableServices`, `fileServices`) |

---

## Naming Conventions

- **snake_case** for all module, variable, and resource names.
- **Colons** (`:`) for object/map attribute assignment — not equals signs (`=`).
- **`format()`** instead of string interpolation (`"${...}"`).
- All resource names come from the NGC naming service: `var.__ngc.environment_details.user_parameters.naming_service.<category>.<key>`.
- Tags always come from `local.tags` (sourced from `var.__ngc.environment_details.system_parameters.TAGS`).

---

## Network Configuration

### AKS Subnet

The AKS subnet ARM path is set per environment in `config.auto.tfvars`:

```hcl
# dev / qa / stage — non-prod subscription
aks_subnet_id = "/subscriptions/<nonprod_id>/resourceGroups/.../subnets/aks"

# prod — prod subscription
aks_subnet_id = "/subscriptions/<prod_id>/resourceGroups/.../subnets/aks"
```

### Subnet References

All other subnets are referenced by **name key**, not ARM path. The name key matches the suffix of the colon-delimited string in `var.__ngc.subnets`:

```hcl
# __ngc.subnets entry: "/subscriptions/.../subnets/redis-subnet:redis-subnet"
# Reference in enabled_modules:
redis_subnet : "redis-subnet"

# Resolved in main.tf locals:
local.subnets = { "redis-subnet" : "/subscriptions/.../subnets/redis-subnet" }

# Used in modules:
subnet_id = data.azurerm_subnet.subnet[var.enabled_modules.redis_subnet].id
```

---

## Placeholder Replacement

All org-specific values use `__PLACEHOLDER_NAME__` tokens. To fill them in:

1. Edit `placeholders.env` with real values.
2. Run: `bash scripts/replace_placeholders.sh`

To replace a single value manually:
```bash
sed -i 's|__TFE_HOSTNAME__|tfe.example.com|g' infrastructure/dev/provider.tf
```

The script uses `|` as the sed delimiter so ARM paths containing `/` are handled safely.
