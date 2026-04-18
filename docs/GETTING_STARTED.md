# Getting Started

Stand up a dev environment from a fresh clone in roughly 10 minutes.

---

## Clone-and-go in 5 steps

1. Fork & clone this repo.

2. Edit ONE file per env: `infrastructure/<env>/config.auto.tfvars`.
   Replace the example values (Azure object IDs, subscription, subnet
   ARM path, CIDRs) with your own.

3. Edit `infrastructure/<env>/databricks/config.auto.tfvars` (Databricks
   workspace ID and user).

4. Retarget the Terraform Enterprise registry once across all `.tf` files:
   ```bash
   find infrastructure -name '*.tf' -exec sed -i.bak \
     -e 's|west.tfe.nginternal.com|<your-tfe-hostname>|g' \
     -e 's|/platform/|/<your-tfe-org>/|g' {} +
   find infrastructure -name '*.tf.bak' -delete
   ```

5. In the GitHub UI, create four Environments (`dev`, `qa`, `stage`,
   `prod`) and set the variables and secrets below on each.

> **Note — `var.__ngc`:** This variable (naming service, tags, subnets,
> resource groups) is injected automatically by Terraform Enterprise at
> plan/apply time. It is owned by the NGC platform team and you never set
> it yourself. If you are running outside TFE, ask your platform team to
> provision a workspace for your product — they will attach the correct
> `__ngc` workspace variable.

---

## Required GitHub Environment configuration (per env)

**Variables:**

| Name | Example |
|------|---------|
| `GH_ORG` | `ng-cloud-platform` |
| `REUSABLE_WORKFLOWS_REPO` | `terraform-reusable-workflows` |
| `RUNNER_GROUP` | `dds-rca` (non-prod) / `dds-rca-prod` (prod) |
| `GIT_FOLDER` | `infrastructure/dev/` |
| `GIT_ID` | `obs` |
| `GH_ENVIRONMENT` | `dev` |
| `APP_NAME` | `risk-control-assessment` |
| `TFE_ORG` | `platform` |
| `TFE_HOSTNAME` | `west.tfe.nginternal.com` |
| `TERRAFORM_VERSION` | `1.9.0` |

**Secrets:**

| Name | Purpose |
|------|---------|
| `AZURE_CLIENT_ID` | OIDC federated app reg |
| `AZURE_TENANT_ID` | Azure AD tenant |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `TFE_TOKEN` | Terraform Enterprise team token |
| `INFRACOST_API_KEY` | (only if infracost.yml enabled) |
| `GITLEAKS_LICENSE` | (only if using Gitleaks Pro) |

That's it. No `.tf` or workflow YAML edits required for normal use.

---

## 1. Fork and Clone

```bash
gh repo fork <upstream-org>/risk_control_assessment_agentic_iac --clone --remote
cd risk_control_assessment_agentic_solution_iac
```

Or use GitHub Codespaces — click **Code → Create Codespace on main**. The
`.devcontainer` provisions every tool automatically.

---

## 2. Bootstrap Local Tools

```bash
make bootstrap
```

Verifies and installs: `terraform`, `tflint`, `trivy`, `gh`, `az`, `infracost`,
`pre-commit`. Also runs `pre-commit install` and initialises the tflint Azure plugin.

---

## 3. Authenticate

```bash
az auth login           # Azure CLI — if not already logged in
az login                # interactive browser login
```

**If using Terraform Enterprise:**
```bash
terraform login <tfe-hostname>
```

**If NOT using Terraform Enterprise**, follow `docs/OIDC_AZURE_FEDERATION.md`
to wire GitHub Actions directly into Azure with short-lived OIDC tokens.

---

## 4. Configure the Dev Environment

Open `infrastructure/dev/config.auto.tfvars` and fill in:

| Key | Description |
|-----|-------------|
| `tfe_hostname` | Your Terraform Enterprise registry hostname |
| `tfe_org` | Your Terraform Enterprise organisation name |
| `spn_object_id` | Azure AD object ID of the deployment service principal |
| `aks_spn_object_id` | Azure AD object ID of the AKS cluster service principal |
| `org_public_ip_cidrs` | List of org egress CIDRs |
| `aks_subnet_id` | Full ARM path of the AKS subnet your platform provisioned |
| `keyvault_admins_app` | Map of `{ logical_name = "azure-ad-object-id" }` for Key Vault admins |
| `keyvault_admins_byok` | Same map for the BYOK vault |
| `enabled_modules` | Feature flags — start with `byok = true`, then `diagnostic_logging = true` |

Enable modules incrementally — `byok` must be `true` before enabling any
CMK-backed resource (`storage_account`, `postgres`, `service_bus`, etc.).

---

## 5. Validate Locally

```bash
make validate ENV=dev     # terraform init -backend=false && terraform validate
make lint                 # tflint --recursive
make security             # trivy config CRITICAL/HIGH
INFRACOST_API_KEY=<key> make cost ENV=dev   # optional cost estimate
```

---

## 6. Open a PR

CI (`.github/workflows/terraform-ci.yml`) runs on every PR:

- `terraform fmt --check` — all envs
- `terraform validate` — all envs (no backend)
- `tflint --recursive` — all infrastructure
- `trivy config` — SARIF upload to Code Scanning

All checks must pass **and** CODEOWNERS must approve before merge.

---

## 7. Apply

Apply is a deliberate **manual** action after merge:

1. Go to **Actions → Terraform Apply Dev → Run workflow**.
2. `terraform apply` runs against the TFE workspace for the environment.
3. Verify outputs in the TFE run log and confirm Key Vault secrets are populated.

---

## 8. Promote dev → qa → stage → prod

Promotion is a PR that edits only the target env's `config.auto.tfvars`
(e.g. flipping a flag from `false` to `true` in `qa/config.auto.tfvars`).
Each env has its own plan / apply workflow pair.

---

## Drift Detection

`.github/workflows/terraform-drift.yml` runs `terraform plan --detailed-exitcode`
against every environment daily at 06:00 UTC. If Azure state diverges from
Terraform (someone changed a resource in the portal), a GitHub Issue tagged
`drift` is opened automatically.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `tflint` errors on `azurerm_*` rules | Run `tflint --init` to re-download the Azure ruleset |
| `terraform init` fails on module source | Your TFE token lacks access to the `platform/` registry — request access from your platform team |
| `terraform validate` fails with "missing required argument" | A flag in `enabled_modules` is `true` but the required subnet key is `null` — set the subnet key string |
| Drift issue opened on first run | The environment has never been applied — `enabled_modules` values don't match actual Azure state yet; apply to sync |
| `infranot diff` shows no changes | The diff tool requires `INFRANOT_API_KEY` secret to be set in repo settings |
| Pre-commit hook blocks commit | Run `pre-commit run --all-files` to see and fix all violations before committing |
