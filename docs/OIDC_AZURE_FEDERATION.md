# OIDC Azure Federation

Use this guide when you fork this repo and do **not** use Terraform Enterprise.
Workload Identity Federation lets GitHub Actions authenticate to Azure with
short-lived OIDC tokens — no long-lived secrets stored in the repo.

---

## 1. Create an Azure AD Application and Service Principal

```bash
# Create the app registration
az ad app create --display-name "ghs-rca-iac"

# Capture the app (client) ID
APP_ID=$(az ad app list --display-name "ghs-rca-iac" --query "[0].appId" -o tsv)

# Create the service principal
az ad sp create --id "$APP_ID"

# Assign Contributor on your subscription (tighten scope as needed)
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/<your-subscription-id>"
```

---

## 2. Register a Federated Credential per Environment

Repeat for **dev**, **qa**, **stage**, and **prod**:

```bash
for ENV in dev qa stage prod; do
  cat > "fic-${ENV}.json" <<EOF
{
  "name": "ghs-rca-iac-${ENV}",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<your-org>/<your-fork>:environment:${ENV}",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
  az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "fic-${ENV}.json"
  rm "fic-${ENV}.json"
done
```

> The `subject` must match the GitHub Actions environment name exactly.

---

## 3. Populate Repo Secrets

```bash
gh secret set AZURE_CLIENT_ID       --body "$APP_ID"
gh secret set AZURE_TENANT_ID       --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --body "<your-subscription-id>"
```

---

## 4. Swap the Workflow Auth Block

In both `terraform-plan-*.yml` and `terraform-apply-*.yml`, replace the TFE
reusable-workflow call with the following pattern:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: dev   # matches the federated credential subject
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: terraform init
        working-directory: infrastructure/dev
        run: terraform init -input=false
        env:
          ARM_USE_OIDC:        "true"
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: terraform plan
        working-directory: infrastructure/dev
        run: terraform plan -no-color -input=false
        env:
          ARM_USE_OIDC:        "true"
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

---

## 5. Add an Azure Storage Remote Backend (Recommended)

Without TFE you need a remote backend so state is shared across runs.

```bash
# Create a resource group and storage account for state
az group create --name rca-tfstate --location eastus2

az storage account create \
  --name <your-tfstate-account> \
  --resource-group rca-tfstate \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name tfstate \
  --account-name <your-tfstate-account>
```

Create `infrastructure/dev/backend.tf` (this file is in `.gitignore` — do **not** commit it):

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rca-tfstate"
    storage_account_name = "<your-tfstate-account>"
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
    use_oidc             = true
  }
}
```

Repeat for `qa/`, `stage/`, `prod/` with the appropriate `key` value.
