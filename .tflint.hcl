plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

config {
  format              = "compact"
  module_type         = "local"
  disabled_by_default = false
}

rule "terraform_required_version"     { enabled = true }
rule "terraform_required_providers"   { enabled = true }
rule "terraform_naming_convention"    { enabled = true }
rule "terraform_missing_comments"     { enabled = true }
rule "terraform_deprecated_index"     { enabled = true }
rule "terraform_unused_declarations"  { enabled = true }
rule "terraform_documented_variables" { enabled = false }
