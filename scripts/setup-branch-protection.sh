#!/usr/bin/env bash
# Applies branch-protection rules to 'main' via the GitHub CLI.
# Run once after forking this repo (requires: gh auth login + repo admin rights).

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "==> Applying branch protection to ${REPO}@main"

gh api "repos/${REPO}/branches/main/protection" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "fmt + validate (dev)",
      "fmt + validate (qa)",
      "fmt + validate (stage)",
      "fmt + validate (prod)",
      "tflint",
      "trivy config"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_code_owner_reviews": true
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "Done. Verify in GitHub UI: Settings → Branches → Branch protection rules."
