#!/usr/bin/env bash
# =============================================================================
# replace_placeholders.sh — Substitute all __PLACEHOLDER__ tokens in the repo.
#
# Usage:
#   1. Fill in all values in ../placeholders.env
#   2. Run: bash scripts/replace_placeholders.sh
#
# The script uses | as the sed delimiter to safely handle values that contain
# forward slashes (e.g. ARM resource IDs, subnet paths).
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACEHOLDER_FILE="${REPO_ROOT}/placeholders.env"

if [[ ! -f "${PLACEHOLDER_FILE}" ]]; then
  echo "ERROR: ${PLACEHOLDER_FILE} not found." >&2
  exit 1
fi

# Source the env file to load all variable values.
# shellcheck source=../placeholders.env
source "${PLACEHOLDER_FILE}"

# Validate: every variable must be non-empty.
required_vars=(
  TFE_HOSTNAME TFE_ORG
  GH_ORG GH_REUSABLE_REPO RUNNER_GROUP_NONPROD RUNNER_GROUP_PROD
  NONPROD_SUBSCRIPTION_ID NONPROD_AKS_SUBNET_ID
  PROD_SUBSCRIPTION_ID PROD_AKS_SUBNET_ID
  SPM_OBJECT_ID AKS_SPM_OBJECT_ID
  KEYVAULT_ADMIN_1_NAME KEYVAULT_ADMIN_1_OBJECT_ID
  KEYVAULT_ADMIN_2_NAME KEYVAULT_ADMIN_2_OBJECT_ID
  PLATFORM_ADMINS_OBJECT_ID
  ORG_PUBLIC_IP_CIDR ORG_PUBLIC_IP_START ORG_PUBLIC_IP_END
  ORG_INTERNAL_IP_START ORG_INTERNAL_IP_END
  AKS_IP_START AKS_IP_END
  DATABRICKS_WORKSPACE_RESOURCE_ID DATABRICKS_WORKSPACE_URL
  DATABRICKS_ADMIN_EMAIL DATABRICKS_ADMIN_KEY
  SYNAPSE_INDIA_WEST_IP_START SYNAPSE_INDIA_WEST_IP_END
  SYNAPSE_US_WEST_IP_START SYNAPSE_US_WEST_IP_END
  SYNAPSE_US_CENTRAL_IP_START SYNAPSE_US_CENTRAL_IP_END
)

missing=()
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("${var}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: The following values are empty in placeholders.env:" >&2
  for m in "${missing[@]}"; do
    echo "  - ${m}" >&2
  done
  exit 1
fi

# Collect all target files (.tf, .tfvars, .yml, .yaml).
# Exclude the .terraform working directory and this script itself.
mapfile -t FILES < <(
  find "${REPO_ROOT}" -type f \( \
    -name "*.tf" -o \
    -name "*.tfvars" -o \
    -name "*.yml" -o \
    -name "*.yaml" \
  \) \
  ! -path "*/.terraform/*" \
  ! -path "*/node_modules/*"
)

replace_in_files() {
  local placeholder="${1}"
  local value="${2}"
  for f in "${FILES[@]}"; do
    # Only process files that actually contain the placeholder (faster).
    if grep -qF "${placeholder}" "${f}" 2>/dev/null; then
      sed -i "s|${placeholder}|${value}|g" "${f}"
    fi
  done
}

echo "Replacing placeholders in ${#FILES[@]} files..."

# ── Terraform Enterprise ──────────────────────────────────────────────────────
replace_in_files "__TFE_HOSTNAME__"  "${TFE_HOSTNAME}"
replace_in_files "__TFE_ORG__"       "${TFE_ORG}"

# ── GitHub Actions ────────────────────────────────────────────────────────────
replace_in_files "__GH_ORG__"               "${GH_ORG}"
replace_in_files "__GH_REUSABLE_REPO__"     "${GH_REUSABLE_REPO}"
replace_in_files "__RUNNER_GROUP_NONPROD__" "${RUNNER_GROUP_NONPROD}"
replace_in_files "__RUNNER_GROUP_PROD__"    "${RUNNER_GROUP_PROD}"

# ── Azure Subscriptions & Subnets ─────────────────────────────────────────────
replace_in_files "__NONPROD_SUBSCRIPTION_ID__" "${NONPROD_SUBSCRIPTION_ID}"
replace_in_files "__NONPROD_AKS_SUBNET_ID__"   "${NONPROD_AKS_SUBNET_ID}"
replace_in_files "__PROD_SUBSCRIPTION_ID__"    "${PROD_SUBSCRIPTION_ID}"
replace_in_files "__PROD_AKS_SUBNET_ID__"      "${PROD_AKS_SUBNET_ID}"

# ── Service Principals ────────────────────────────────────────────────────────
replace_in_files "__SPM_OBJECT_ID__"     "${SPM_OBJECT_ID}"
replace_in_files "__AKS_SPM_OBJECT_ID__" "${AKS_SPM_OBJECT_ID}"

# ── Key Vault Admins ──────────────────────────────────────────────────────────
replace_in_files "__KEYVAULT_ADMIN_1_NAME__"      "${KEYVAULT_ADMIN_1_NAME}"
replace_in_files "__KEYVAULT_ADMIN_1_OBJECT_ID__" "${KEYVAULT_ADMIN_1_OBJECT_ID}"
replace_in_files "__KEYVAULT_ADMIN_2_NAME__"      "${KEYVAULT_ADMIN_2_NAME}"
replace_in_files "__KEYVAULT_ADMIN_2_OBJECT_ID__" "${KEYVAULT_ADMIN_2_OBJECT_ID}"

# ── Platform Admins ───────────────────────────────────────────────────────────
replace_in_files "__PLATFORM_ADMINS_OBJECT_ID__" "${PLATFORM_ADMINS_OBJECT_ID}"

# ── Network / IP Ranges ───────────────────────────────────────────────────────
replace_in_files "__ORG_PUBLIC_IP_CIDR__"      "${ORG_PUBLIC_IP_CIDR}"
replace_in_files "__ORG_PUBLIC_IP_START__"     "${ORG_PUBLIC_IP_START}"
replace_in_files "__ORG_PUBLIC_IP_END__"       "${ORG_PUBLIC_IP_END}"
replace_in_files "__ORG_INTERNAL_IP_START__"   "${ORG_INTERNAL_IP_START}"
replace_in_files "__ORG_INTERNAL_IP_END__"     "${ORG_INTERNAL_IP_END}"
replace_in_files "__AKS_IP_START__"            "${AKS_IP_START}"
replace_in_files "__AKS_IP_END__"              "${AKS_IP_END}"

# ── Databricks ────────────────────────────────────────────────────────────────
replace_in_files "__DATABRICKS_WORKSPACE_RESOURCE_ID__" "${DATABRICKS_WORKSPACE_RESOURCE_ID}"
replace_in_files "__DATABRICKS_WORKSPACE_URL__"         "${DATABRICKS_WORKSPACE_URL}"
replace_in_files "__DATABRICKS_ADMIN_EMAIL__"           "${DATABRICKS_ADMIN_EMAIL}"
replace_in_files "__DATABRICKS_ADMIN_KEY__"             "${DATABRICKS_ADMIN_KEY}"

# ── Synapse Regional IP Ranges ────────────────────────────────────────────────
replace_in_files "__SYNAPSE_INDIA_WEST_IP_START__"  "${SYNAPSE_INDIA_WEST_IP_START}"
replace_in_files "__SYNAPSE_INDIA_WEST_IP_END__"    "${SYNAPSE_INDIA_WEST_IP_END}"
replace_in_files "__SYNAPSE_US_WEST_IP_START__"     "${SYNAPSE_US_WEST_IP_START}"
replace_in_files "__SYNAPSE_US_WEST_IP_END__"       "${SYNAPSE_US_WEST_IP_END}"
replace_in_files "__SYNAPSE_US_CENTRAL_IP_START__"  "${SYNAPSE_US_CENTRAL_IP_START}"
replace_in_files "__SYNAPSE_US_CENTRAL_IP_END__"    "${SYNAPSE_US_CENTRAL_IP_END}"

echo "Done. All placeholders replaced."
echo ""
echo "Next steps:"
echo "  1. Review git diff to verify replacements look correct."
echo "  2. Update placeholders.env to reflect the values used (for documentation)."
echo "  3. Run: terraform -chdir=infrastructure/dev init"
