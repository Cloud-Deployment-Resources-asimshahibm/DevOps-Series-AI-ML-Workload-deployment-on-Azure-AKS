resource_group_name  = "aiml-global-rg"
storage_account_name = "__TFSTATE_STORAGE_ACCOUNT__" # scripts/configure.sh (= terraform/global output)
container_name       = "tfstate"
key                  = "stack/dev/terraform.tfstate"
use_azuread_auth     = true # shared keys are disabled; blob leases lock the state
