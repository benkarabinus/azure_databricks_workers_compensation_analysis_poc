# Provider configuration.
#
# azurerm authenticates with your Azure CLI session (`az login`). In azurerm 4.x
# a subscription must be selected: either set `subscription_id` below (via
# terraform.tfvars) or export ARM_SUBSCRIPTION_ID before running Terraform.
#
# The databricks provider targets the workspace created in this same
# configuration and reuses the Azure CLI token (no PAT required) by referencing
# the workspace resource ID. See "special configurations for Azure":
#   https://registry.terraform.io/providers/databricks/databricks/latest/docs#special-configurations-for-azure

provider "azurerm" {
  features {}

  # Use Microsoft Entra ID (not account keys) for storage data-plane operations,
  # so this works on subscriptions whose policy forbids shared-key auth.
  storage_use_azuread = true

  # When null, the provider falls back to the ARM_SUBSCRIPTION_ID env var.
  subscription_id = var.subscription_id
}

# azapi talks directly to the Azure ARM API. We use it for the Databricks
# workspace so we can set computeMode = "Serverless" - a property the azurerm
# provider does not expose yet.
provider "azapi" {
  subscription_id = var.subscription_id
}

provider "databricks" {
  # Resolves the workspace host automatically and authenticates with Azure CLI.
  # auth_type pins Azure CLI auth so a stale ~/.databrickscfg profile or
  # DATABRICKS_* env var can't be picked up instead.
  azure_workspace_resource_id = azapi_resource.workspace.id
  auth_type                   = "azure-cli"
}
