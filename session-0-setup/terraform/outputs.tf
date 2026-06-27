# Outputs printed after `terraform apply`.

output "resource_group_name" {
  description = "Resource group containing the POC resources."
  value       = local.resource_group_name
}

output "workspace_url" {
  description = "Azure Databricks workspace URL. Open this to start Session 1."
  value       = "https://${azapi_resource.workspace.output.properties.workspaceUrl}"
}

output "workspace_id" {
  description = "Azure resource ID of the Databricks workspace."
  value       = azapi_resource.workspace.id
}

output "storage_account_name" {
  description = "Name of the dedicated ADLS Gen2 account (backs both landing and managed containers)."
  value       = azurerm_storage_account.this.name
}

output "external_location_name" {
  description = "Unity Catalog landing external location name."
  value       = databricks_external_location.landing.name
}

output "external_location_url" {
  description = "abfss:// URL registered as the landing external location (container root)."
  value       = databricks_external_location.landing.url
}

output "landing_path" {
  description = "Set the pipelines' landing_path widget to this value (matches common/config.py)."
  value       = "${trimsuffix(databricks_external_location.landing.url, "/")}/state-fund-poc"
}

output "managed_external_location_url" {
  description = "abfss:// URL of the external location backing Unity Catalog managed storage."
  value       = databricks_external_location.managed.url
}

output "managed_catalog_location" {
  description = "Use this as the MANAGED LOCATION when creating the catalog in Session 1."
  value       = "${trimsuffix(databricks_external_location.managed.url, "/")}/state_fund_poc"
}
