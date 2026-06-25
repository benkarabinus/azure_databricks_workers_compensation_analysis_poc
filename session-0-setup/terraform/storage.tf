# Dedicated ADLS Gen2 account backing the POC.
#
# One account, two containers (recommended by Unity Catalog best practices, which
# advise keeping managed storage separate from external/landing storage):
#   - landing  : raw source files, registered as an external location.
#   - managed  : Unity Catalog catalog-level managed storage for the Bronze/Silver/
#                Gold managed tables (wired as the catalog MANAGED LOCATION in Session 1).
#
# This account is intentionally SEPARATE from the Unity Catalog metastore's
# default (root) storage. is_hns_enabled = true turns on the hierarchical
# namespace that makes a StorageV2 account an ADLS Gen2 account.
#
# Production note: for storage-intensive workloads, Databricks recommends striping
# managed vs. external storage across SEPARATE accounts (the ~20k req/s limit is
# per-account). Two containers in one account is fine for this synthetic POC.
#
# Docs:
#   https://learn.microsoft.com/azure/storage/blobs/create-data-lake-storage-account
#   https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/best-practices

# Grant the Terraform operator blob DATA access so containers can be created with
# Entra ID auth. Owner/Contributor cover the control plane but not blob data
# actions, which are required because shared-key auth is disabled by policy.
resource "azurerm_role_assignment" "deployer_blob_data" {
  scope                = local.resource_group_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow the role assignment to propagate before the data-plane calls run.
resource "time_sleep" "wait_for_role" {
  depends_on      = [azurerm_role_assignment.deployer_blob_data]
  create_duration = "150s"
}

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true
  min_tls_version          = "TLS1_2"

  # Comply with the no-shared-key policy: use Entra ID for data-plane auth.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  tags = var.tags

  # Ensure the operator has blob data access before the data-plane readiness check.
  depends_on = [time_sleep.wait_for_role]
}

resource "azurerm_storage_container" "landing" {
  name                  = var.landing_container
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "managed" {
  name                  = var.managed_container
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
