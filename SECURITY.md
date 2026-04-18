# Security Policy

## Supported Versions

Only the `main` branch is supported. All deployments flow from `main` via
Terraform Enterprise (plan on PR, apply on manual dispatch).

## Reporting a Vulnerability

Do not open a public GitHub issue for security vulnerabilities.

- Email your org's security inbox or use GitHub private-vulnerability-reporting if enabled.
- We aim to acknowledge reports within 2 business days and to provide a
  remediation timeline within 10 business days.

## Scope

This repository provisions Azure infrastructure for a risk-control / fraud-assessment platform. In-scope concerns:

- Misconfigured network ACLs or firewall rules that expose resources publicly
- Incorrect Key Vault access policies granting excessive permissions
- Secrets baked in `.tf` / `.tfvars` / variable files — object IDs and subscription IDs committed in plain text
- `.gitignore` missing entries that put Terraform state at risk
- `.tf` files checked into the wrong repo

Out of scope (other repos handle their own threat surfaces):
- Application runtime / frontend / Databricks notebook vulnerabilities → `risk_control_assessment_agentic_solution`
- Argo CD ApplicationSets, Helm chart misconfigurations → `risk_control_assessment_agentic_solution_gitops`
- CVEs in Python / Node app packages, running container images → not here

## Secure Defaults Enforced by This Repo

- **Key Vaults:** `purge_protection_enabled = true`, `default_action = "Deny"`
- **BYOK:** All eligible resources route CMK encryption through the BYOK vault
- **PostgreSQL Flexible Server:** SSL auth enabled, CMK protection, no public endpoint
- **Diagnostic Logging:** Log Analytics Workspace per env; all resources log via `diagnostic_logging` flag
- **Storage:** `public_network_access_enabled = false`, HNS enabled, CMK via BYOK

## Automation

Every PR runs:
- `terraform fmt --check` and `terraform validate` for each env (no backend)
- `tflint --recursive` across all infrastructure
- `trivy config` with SARIF upload to GitHub Code Scanning (CRITICAL / HIGH / MEDIUM)
- Daily drift detection cron at 06:00 UTC — opens a GitHub Issue tagged `drift` on divergence

CODEOWNERS gates every merge to `main`.

## Secrets

Secrets belong in Azure Key Vault, never in this repo. The `key-vault-secret`
modules in `infrastructure/dev/keyvault.tf` (and siblings) write passwords,
connection strings, and workspace URLs into the vault at apply time.
