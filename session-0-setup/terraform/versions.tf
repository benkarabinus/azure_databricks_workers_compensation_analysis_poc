# Terraform and provider version constraints for Session 0.
#
# Two providers are used:
#   - azurerm    : provisions the Azure resource group, ADLS Gen2 account,
#                  Databricks workspace, and the access connector (managed identity).
#   - databricks : registers the Unity Catalog storage credential and external
#                  locations against the newly created workspace.
#   - time       : adds short propagation delays after RBAC role assignments.
#
# Docs:
#   https://learn.microsoft.com/azure/databricks/dev-tools/terraform/
#   https://registry.terraform.io/providers/databricks/databricks/latest/docs

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.118"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}
