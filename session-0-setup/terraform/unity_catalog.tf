# Unity Catalog external location wiring.
#
# Flow (per Databricks guidance):
#   1. Access connector with a system-assigned managed identity.
#   2. Azure RBAC role assignments grant that identity access to the storage
#      account (data plane) and to file-event resources.
#   3. A Unity Catalog storage credential wraps the managed identity.
#   4. A Unity Catalog external location binds the abfss:// path to the credential.
#
# Docs:
#   https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities
#   https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/external-locations-adls
#   https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/unity-catalog-azure

# --- 1. Managed identity Unity Catalog uses to reach the storage account ------
resource "azurerm_databricks_access_connector" "this" {
  name                = local.access_connector_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# --- 2. Grant the identity access to the landing storage account --------------
# Role assignments are scoped to the whole storage account, so they cover both
# the landing and managed containers. Read/write the data itself.
resource "azurerm_role_assignment" "blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# The next two roles let Unity Catalog configure managed file events
# (used by Auto Loader file notifications in later sessions).
resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "eventgrid_contributor" {
  scope                = local.resource_group_id
  role_definition_name = "EventGrid EventSubscription Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# Wait for the access connector's RBAC role assignments to propagate to the
# storage data plane before Databricks validates the external locations
# (otherwise validation can race the grant and fail with a 403).
resource "time_sleep" "wait_for_connector_roles" {
  depends_on = [
    azurerm_role_assignment.blob_data_contributor,
    azurerm_role_assignment.storage_account_contributor,
  ]
  create_duration = "300s"
}

# --- 3. Unity Catalog storage credential (wraps the managed identity) ---------
resource "databricks_storage_credential" "this" {
  name = azurerm_databricks_access_connector.this.name

  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.this.id
  }

  comment = "Managed identity credential for the State Fund POC landing zone (Terraform-managed)."

  depends_on = [
    azurerm_role_assignment.blob_data_contributor,
    azurerm_role_assignment.storage_account_contributor,
  ]
}

# --- 4. Unity Catalog external locations --------------------------------------
# Landing: raw source files (Auto Loader reads these in Session 1).
resource "databricks_external_location" "landing" {
  name            = "${var.prefix}_landing"
  url             = "abfss://${azurerm_storage_container.landing.name}@${azurerm_storage_account.this.name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.this.name
  comment         = "State Fund POC landing zone (Terraform-managed)."

  # Allow teardown even if soft-deleted (retained) tables still count as dependents.
  force_destroy = true

  depends_on = [
    databricks_storage_credential.this,
    time_sleep.wait_for_connector_roles,
  ]
}

# Managed: backs Unity Catalog catalog-level managed storage. Session 1 sets the
# catalog's MANAGED LOCATION to a subpath under this external location, so the
# Bronze/Silver/Gold managed tables physically land here.
resource "databricks_external_location" "managed" {
  name            = "${var.prefix}_managed"
  url             = "abfss://${azurerm_storage_container.managed.name}@${azurerm_storage_account.this.name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.this.name
  comment         = "State Fund POC managed storage for Bronze/Silver/Gold (Terraform-managed)."

  # Allow teardown even if soft-deleted (retained) managed tables still count as dependents.
  force_destroy = true

  depends_on = [
    databricks_storage_credential.this,
    time_sleep.wait_for_connector_roles,
  ]
}
