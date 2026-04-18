# Multi-Product Deployment

This repo is designed as a reusable template for spinning up 36+ agentic
product solutions without rerunning Terraform from scratch each time.

---

## Why Fork Per Product Instead of Monorepo

| Concern | Fork-per-product | Monorepo |
|---------|-----------------|---------|
| Cost isolation (one billing team per product) | Strong | Weak |
| Continuous boundary per product | Strong | Weak |
| Independent release cadence | Strong | N/A |
| Tool dependency (e.g. Terraform version) | Per-product control | Complex |
| Single admin upgrade path | N/A | Strong |
| Central / drift reporting across all products | Extra tooling needed | Built-in |
| PR blast radius | Small — one product | Large — affects all |

For 36-40 products, fork-per-product is the right tradeoff. Below 10, a
monorepo may be preferable — it is not covered by this template.

---

## Per-Product Fork Checklist

When you fork this template for a new product, change **only** these values:

1. **`infra/settings`** — update the repo description and topics in GitHub.
2. **`infrastructure/<env>/config.auto.tfvars`** — set `aks_subnet_id` and
   `keyvault_admins_*` for the product's network and admin team.
3. **Azure Flags** — in `enabled_modules`, enable 1–3 modules the product needs
   (start with `byok` and `diagnostic_logging`).
4. **Wildcards** — set `INFRANOT_API_KEY`, and (if not using TFE)
   `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as repo secrets.
5. **`keyvault_admins_app`** — add the product team's Azure AD object IDs.
6. **Setup descriptions** — update `docs/GETTING_STARTED.md` with product-specific steps if needed.
7. **`database_name`** — set a product-specific DB name in `config.auto.tfvars`.
8. **Verify** — run `make validate ENV=dev && make lint && make security` locally.

Everything else (`.tf` files, workflows, CI, policies) is identical across all forks.
That is the single most important pattern — do **not** fork-diverge the `.tf` files.

---

## Template Sync — Keeping Forks Up to Date

When this template ships a module bump or security fix, propagate it to all forks
via one of three approaches:

### Option A — Manual git remote (< 10 forks)

```bash
git remote add template-upstream <template-repo-url>
git fetch template-upstream
git merge template-upstream/main
# resolve any conflicts in config.auto.tfvars only
```

### Option B — Scripted sync workflow (10–40 forks)

Add a scheduled workflow to each fork that opens a PR from the template upstream:

```yaml
name: Template Sync
on:
  schedule:
    - cron: "0 6 * * 1"   # every Monday at 06:00 UTC
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: AndreasAugustin/actions-template-sync@v1
        with:
          github_token:    ${{ secrets.NET_GITHUB_TOKEN }}
          source_repo_path: <template-org>/risk_control_assessment_agentic_iac
          pr_labels:       template-sync
```

### Option C — Platform tooling (> 40 forks)

Use Backstage, Port, or a similar internal developer platform to push
template updates to all forks centrally.

---

## Onboarding Checklist for a New Product Team

- [ ] Click **"Use this template"** to create `<product>-iac`.
- [ ] Add the product team to the new repo (GitHub org CODEOWNERS).
- [ ] Ask the platform team to create the product's subnet set.
- [ ] Update `infrastructure/dev/config.auto.tfvars` with the product's subnet keys and admin IDs.
- [ ] Run `make validate ENV=dev` — no cloud state is touched.
- [ ] Run `make lint && make security`.
- [ ] Merge a first PR enabling only `byok` and `diagnostic_logging`.
- [ ] Apply manually via GitHub Actions → Terraform Apply Dev.

---

## Naming Across Environments

Resource naming is handled by the platform's `naming_service` inside
`var.__ngc`. You never write a resource name directly in `.tf` — the
platform gives you globally unique names per product per environment.

```hcl
# Always use — never hardcode a name string:
name = var.__ngc.environment_details.user_parameters.naming_service.<category>.<key>
```

This is the single most important pattern for multi-product scale.
Do **not** override it with literal strings.
