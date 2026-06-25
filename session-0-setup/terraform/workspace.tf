# Azure Databricks workspace.
#
# Premium SKU is required for Unity Catalog and serverless compute. Workspaces
# created today are automatically enabled for Unity Catalog (a storage-less
# default metastore is provisioned per region), and serverless compute is
# available by default in supported regions - no extra enablement step.
#
# Docs:
#   https://learn.microsoft.com/azure/databricks/dev-tools/terraform/azure-workspace
#   https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/get-started
#   https://learn.microsoft.com/azure/databricks/compute/serverless/

resource "azurerm_databricks_workspace" "this" {
  name                = local.workspace_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  sku                 = "premium"
  tags                = var.tags
}
