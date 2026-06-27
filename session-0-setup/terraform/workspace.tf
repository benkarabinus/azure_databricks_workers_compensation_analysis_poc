# Azure Databricks workspace (serverless type).
#
# Created via the azapi provider so we can set computeMode = "Serverless" - a
# true serverless workspace with NO managed resource group, VNet, or DBFS storage
# in your subscription (all compute runs in Databricks' serverless plane). The
# azurerm_databricks_workspace resource only creates classic ("Hybrid") workspaces.
# Unity Catalog is auto-enabled and the workspace fully supports external locations.
#
# Docs:
#   https://learn.microsoft.com/azure/databricks/admin/workspace/serverless-workspaces
#   https://learn.microsoft.com/azure/templates/microsoft.databricks/workspaces
#   https://learn.microsoft.com/azure/databricks/compute/serverless/

resource "azapi_resource" "workspace" {
  type      = "Microsoft.Databricks/workspaces@2026-01-01"
  name      = local.workspace_name
  parent_id = local.resource_group_id
  location  = local.resource_group_location

  body = {
    sku = {
      name = "premium"
    }
    properties = {
      # Required on create and immutable. "Serverless" => no classic compute plane.
      computeMode = "Serverless"
    }
  }

  tags = var.tags

  # Capture the workspace host for the databricks provider + outputs.
  response_export_values = ["properties.workspaceUrl"]
}
