# Contributing

Thanks for helping improve this IaC. Read this once before your first PR.

## Scope

This repo owns infrastructure for Azure resources only. Before you open a PR,
confirm the change belongs here:

| Change type | Correct repo |
|-------------|-------------|
| App / API / UI / multi-service code | `risk_control_assessment_agentic_solution` |
| Helm charts / Argo CD / image-tag updates | `risk_control_assessment_agentic_solution_gitops` |
| Terraform modules, per-env plan / apply / vCluster workflows | **this repo** |

If a PR touches Helm, Dockerfiles, or app source, close it and open in the correct repo.

## Prerequisites

- Terraform >= 1.6
- Access to the Terraform Enterprise org that hosts the `platform/` module registry
  (every `source = "__TFE_HOSTNAME__/__TFE_ORG__/..."` pulls from there)
- An Azure subscription with the subnets referenced in `config.auto.tfvars`
  already provisioned by your platform team

Run `make bootstrap` to install and verify all local tools.

## Branching

- `main` is protected. Every change goes through a PR.
- Branch naming: `feat/short-desc`, `fix/short-desc`, `infra/short-desc`
- Commit messages must follow Conventional Commit format:
  `feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `build:`, `revert:`

## Local Checks Before Opening a PR

```bash
make validate ENV=dev
make lint
make security
```

Or manually for all envs:

```bash
for e in dev qa stage prod; do
  (cd infrastructure/$e && terraform init -backend=false && terraform validate)
done
tflint --recursive infrastructure
trivy config --exit-code 1 --severity CRITICAL,HIGH infrastructure
```

## What CI Enforces

Every PR must pass all jobs in `.github/workflows/terraform-ci.yml`:

1. `terraform fmt --check` — all envs
2. `terraform validate` — all envs (no backend)
3. `tflint --recursive` — all infrastructure
4. `trivy config` — CRITICAL / HIGH / MEDIUM severity

A PR cannot merge until all checks pass **and** CODEOWNERS has approved.

## Adding a New Module

See the **Adding New Modules** section in `README.md`. In brief:

1. Add a flag to `enabled_modules` in `variables.tf` as `optional(bool, false)`.
2. Set it to `false` in `config.auto.tfvars` for all four environments.
3. Create `new_module.tf` in `infrastructure/dev/` using the `for_each` ternary pattern.
4. Add an `output "outputs_new_module"` block following the established pattern.
5. Copy the `.tf` file identically to `qa/`, `stage/`, `prod/`.
6. Set the flag to `true` only in the target env's `config.auto.tfvars`.

## Secrets

Never commit secrets, `backend.tf`, `backend.hcl`, `.tfstate`, or `.tfvars`
with real values — they are already in `.gitignore`.

Passwords, connection strings, and workspace URLs are written to the application
Key Vault by the `key-vault-secret` modules at apply time.

## Review

All changes that touch `network_acls`, `access_policies`, or firewall rules
get an extra look from the infrastructure security team — flag these explicitly
in the PR description.
