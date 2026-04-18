#!/usr/bin/env bash
# Installs and validates all local developer prerequisites.
# Run via:  make bootstrap  OR  bash scripts/bootstrap.sh

set -euo pipefail

echo "==> Bootstrapping risk-control-assessment IaC toolchain"

missing=()

check() {
  if ! command -v "$1" &>/dev/null; then
    missing+=("$1")
    echo "  MISSING: $1"
  else
    echo "  OK:      $1 ($(command -v "$1"))"
  fi
}

check terraform
check tflint
check trivy
check gh
check az
check infracost
check pre-commit

if [[ ${#missing[@]} -gt 0 ]]; then
  echo ""
  echo "Install missing tools, then re-run this script."
  echo "Suggested:"
  echo "  terraform  → https://developer.hashicorp.com/terraform/downloads"
  echo "  tflint     → brew install tflint  OR  https://github.com/terraform-linters/tflint"
  echo "  trivy      → brew install trivy   OR  https://aquasecurity.github.io/trivy"
  echo "  gh         → brew install gh"
  echo "  az         → https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  echo "  infracost  → https://www.infracost.io/docs"
  echo "  pre-commit → pip install pre-commit"
  exit 1
fi

echo ""
echo "==> Installing pre-commit hooks"
pre-commit install
pre-commit install --hook-type commit-msg

echo ""
echo "==> Initialising tflint plugins"
if [[ -f .tflint.hcl ]]; then
  tflint --init
else
  echo "  SKIP: .tflint.hcl not found"
fi

echo ""
echo "==> Verifying pre-commit config syntax"
pre-commit validate-config

echo ""
echo "==> Bootstrap complete. Next steps:"
echo "  1. az auth login                           # if not already logged in"
echo "  2. az login vault.tfe.azinteract.com       # TFE token (if using TFE)"
echo "     OR follow docs/OIDC_AZURE_FEDERATION.md for OIDC without TFE"
echo "  3. Edit infrastructure/dev/config.auto.tfvars:"
echo "       aks_subnet_id        — full ARM path of your AKS subnet"
echo "       keyvault_admins_app  — map of { name : azure-ad-object-id }"
echo "       keyvault_admins_byok — same for BYOK vault"
echo "       enabled_modules      — flip flags from false to true (byok first, then diagnostic_logging)"
echo "  4. make validate ENV=dev"
echo "  5. make lint && make security"
echo "  6. Open a PR targeting main"
