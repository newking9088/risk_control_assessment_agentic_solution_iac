# =============================================================================
# provider.tf — Terraform core settings and AzureRM provider configuration.
#
# All environments (dev / qa / stage / prod) use this identical file.
# Environment differences live exclusively in config.auto.tfvars.
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3"
    }
  }
}

provider "azurerm" {
  version = "~> 3"

  features {
    key_vault {
      # Allow Terraform to recover a soft-deleted vault instead of failing on re-create.
      recover_soft_deleted_key_vaults = true
      # Remove soft-delete tombstone on destroy so the name can be reused immediately.
      purge_soft_delete_on_destroy    = true
    }
  }
}
