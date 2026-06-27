---
title: Session 0 — Setup
layout: default
nav_order: 3
---

# Session 0 — Environment Readiness (Terraform)

**Goal:** Provision the Azure foundation for the POC with Terraform — a serverless
Azure Databricks workspace plus a **dedicated ADLS Gen2 account** registered as a Unity Catalog
**external location** (the landing zone Session 1 ingests from).

**Output:** A running serverless workspace (Unity Catalog auto‑enabled) and a
validated external location pointing at `abfss://landing@<storage>.dfs.core.windows.net/`.

All assets live under `session-0-setup/terraform/` in the repository and are created with
`terraform apply`. Optionally tear everything down with `terraform destroy` when finished.

## What Terraform provisions

| Resource | Terraform | Purpose |
| --- | --- | --- |
| Resource group | `azurerm_resource_group` (create‑or‑reuse) | Container for all POC resources |
| ADLS Gen2 account + 2 containers | `azurerm_storage_account` (`is_hns_enabled = true`), `azurerm_storage_container` ×2 | Dedicated `landing` (raw files) + `state-fund-poc-managed` (Bronze/Silver/Gold managed tables) storage, **separate** from the metastore root |
| Databricks workspace | `azapi_resource` (`computeMode = "Serverless"`) | True serverless workspace — no managed RG/VNet/DBFS; Unity Catalog auto‑enabled |
| Access connector | `azurerm_databricks_access_connector` (system‑assigned identity) | Managed identity Unity Catalog uses to reach storage |
| Role assignments | `azurerm_role_assignment` ×4 | Grant the connector’s identity blob‑data + file‑event access, and the deployer blob‑data access to create the containers |
| Storage credential | `databricks_storage_credential` | Unity Catalog wrapper around the managed identity |
| External locations | `databricks_external_location` ×2 | `<prefix>_landing` (raw) and `<prefix>_managed` (catalog managed storage) |

### Why these design choices

- **No metastore resource.** Azure Databricks workspaces created today are
  [automatically enabled for Unity Catalog](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/get-started)
  with a storage‑less default metastore per region — so we bring our **own** ADLS account as an
  external location instead of creating a metastore.
- **True serverless workspace.** The workspace is created with `computeMode = "Serverless"` via the
  [azapi](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) provider —
  the `azurerm_databricks_workspace` resource only creates classic (“Hybrid”) workspaces. A
  [serverless workspace](https://learn.microsoft.com/azure/databricks/admin/workspace/serverless-workspaces)
  has **no managed resource group, VNet, or DBFS storage** in your subscription; all compute runs in
  Databricks’ serverless plane. The Premium SKU still backs Unity Catalog, which is auto‑enabled.
- **Managed identity, not keys.** Unity Catalog reaches the storage account through an
  [Azure managed identity](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities)
  on an access connector — no account keys or secrets to rotate.
- **Entra ID storage auth.** The storage account disables shared‑key auth and the `azurerm` provider
  manages the data plane with Microsoft Entra ID (`storage_use_azuread = true`), so it works on
  subscriptions whose Azure Policy forbids key‑based auth. Terraform grants the deploying identity
  **Storage Blob Data Contributor** so it can create the containers.
- **Dedicated storage.** The landing account is intentionally separate from the metastore’s
  default storage, keeping raw source files isolated from managed tables.
- **Managed storage, kept separate from landing.** Bronze/Silver/Gold are **managed tables**, so
  their files live in catalog‑level **managed storage** (the `managed` container).
  [Databricks best practice](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/best-practices)
  is to keep managed storage separate from the raw `landing` external location and to prefer
  catalog‑level managed storage as the unit of isolation. Session 1 sets the catalog’s
  `MANAGED LOCATION` to a subpath of the `managed` external location. (For storage‑intensive
  production workloads, Databricks suggests separate **accounts** rather than just containers.)
- **File events for efficient ingestion.** Granting the connector the `EventGrid EventSubscription
  Contributor` role lets Unity Catalog enable
  [file events](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/manage-external-locations#file-events),
  which provisions an **Event Grid system topic** on the storage account so Auto Loader (Session 1)
  uses event notifications instead of directory listing.
- **Teardown‑friendly.** The external locations set `force_destroy = true`, so `terraform destroy`
  isn’t blocked by soft‑deleted (retained) managed tables that still count as dependents.

## Prerequisites

- **Azure subscription** with permission to create resource groups, storage, a Databricks
  workspace, and **role assignments** (`Owner` or `User Access Administrator` on the target scope —
  required to grant the managed identity its roles).
- **Account‑level Unity Catalog privileges.** Creating the storage credential and external location
  requires `CREATE STORAGE CREDENTIAL` / `CREATE EXTERNAL LOCATION`, held by an
  [account admin or metastore admin](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/manage-privileges/admin-privileges).
- **[Terraform CLI](https://developer.hashicorp.com/terraform/install)** ≥ 1.6.
- **[Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)** — used for authentication.

Both providers authenticate with your Azure CLI session, so no Databricks personal access token is
needed. See the [Databricks Terraform provider](https://learn.microsoft.com/azure/databricks/dev-tools/terraform/).

## Steps

### 1. Sign in to Azure

```powershell
az login
az account set --subscription "<your-subscription-id>"
```

Docs: [Sign in with Azure CLI](https://learn.microsoft.com/cli/azure/authenticate-azure-cli).

### 2. Configure your variables

```powershell
cd session-0-setup/terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```

All resource names are **deterministic** — set explicitly in `terraform.tfvars`, with no autogenerated
suffixes — so review them before applying. `terraform.tfvars` is gitignored. Each variable’s naming
constraint is also documented inline in the file.

**Required — you must set these:**

| Variable | What to set | Constraint |
| --- | --- | --- |
| `subscription_id` | Your Azure subscription (or omit and export `ARM_SUBSCRIPTION_ID`) | GUID |
| `storage_account_name` | A **globally unique** ADLS Gen2 account name | 3–24 lowercase letters/digits |
| `workspace_name` | The Databricks workspace name | 3–64 chars; letters, digits, `-`, `_` |
| `access_connector_name` | The access connector (managed identity) name | 3–64 chars; letters, digits, `-`, `_`, `.` |

**Optional — sensible defaults provided:**

| Variable | Default | Notes |
| --- | --- | --- |
| `prefix` | `sfpoc` | Used only in the external location names (`<prefix>_landing`, `<prefix>_managed`) |
| `location` | `westus2` | Must support Databricks serverless |
| `create_resource_group` | `true` | Set `false` to reuse an existing group |
| `resource_group_name` | `rg-state-fund-poc` | Group to create or reuse |
| `landing_container` | `landing` | 3–63 chars, lowercase letters/digits/hyphens only |
| `managed_container` | `state-fund-poc-managed` | Same container rules (no uppercase or underscores) |
| `tags` | project/env tags | Applied to all resources |

> **`storage_account_name` must be globally unique across all of Azure.** If `terraform apply` reports
> the name is taken, choose another.
>
> **Create‑or‑reuse resource group:** leave `create_resource_group = true` to have Terraform create
> the group, or set it to `false` to deploy into an existing group named `resource_group_name`.

### 3. Initialize and deploy

Initialize the working directory (downloads the providers):

```powershell
terraform init
```

**This configuration creates the Databricks workspace *and* the Unity Catalog objects that live
inside it** (the storage credential and external locations). The `databricks` provider authenticates
against that workspace (`azure_workspace_resource_id`), and creating those Unity Catalog objects
requires **account‑admin privileges** — so the first run is done in **two phases with a one‑time admin
step in between**.

**Phase 1 — create the workspace.** This bootstraps the Azure Databricks **account** and the regional
Unity Catalog **metastore** for your tenant, and gives the `databricks` provider a target to
authenticate against:

```powershell
terraform apply -target='azapi_resource.workspace'
```

> **PowerShell:** quote the target — `-target='azapi_resource.workspace'` — so the shell
> doesn’t split the resource address.

**Between phases — assign account admin (one‑time).** Phase 2 creates Unity Catalog objects, which
require **account‑admin (or metastore‑admin)** privileges — being a subscription `Owner` is *not*
enough. If the person who will run Phase 2 isn’t already an account admin, have a **Microsoft Entra ID
Global Administrator** do this once:

1. Sign in to the **account console** at [accounts.azuredatabricks.net](https://accounts.azuredatabricks.net).
   A Global Administrator’s first sign‑in automatically grants them the **account admin** role
   ([establish the first account admin](https://learn.microsoft.com/en-us/azure/databricks/admin/admin-concepts#establish-first-account-admin)).
2. Open **User management**, select the user (or service principal) who will run Phase 2, and assign
   the **Account admin** role — or grant just `CREATE STORAGE CREDENTIAL` and `CREATE EXTERNAL LOCATION`
   on the metastore.

Skip this if the Phase 2 operator is already an account admin (for example, a demo tenant where you
bootstrapped yourself). Docs:
[admin privileges](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/manage-privileges/admin-privileges).

**Phase 2 — create everything else** (storage, access connector, role assignments, storage credential,
external locations):

```powershell
terraform apply
```

Approve with `yes`. Once the workspace is in state, later changes need only a single `terraform apply`.

> **Auth:** the `databricks` provider is pinned to `auth_type = "azure-cli"`, so it uses your
> `az login` session and ignores any stale `~/.databrickscfg` profile or `DATABRICKS_*` env var
> (a leftover personal access token there otherwise causes `Invalid access token`).

Docs: [init](https://developer.hashicorp.com/terraform/cli/commands/init) ·
[apply](https://developer.hashicorp.com/terraform/cli/commands/apply) ·
[resource targeting](https://developer.hashicorp.com/terraform/cli/commands/plan#resource-targeting).

### 4. Verify

- **Azure portal:** the resource group contains the storage account, workspace, and access connector.
- **Databricks → Catalog → External Locations:** open the `<prefix>_landing` location and click
  **Test connection** — all checks should pass
  ([manage external locations](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/manage-external-locations)).
- **Serverless:** in a new notebook, confirm **Serverless** appears in the compute selector
  ([connect to serverless compute](https://learn.microsoft.com/azure/databricks/compute/serverless/)).

### 5. Record the outputs for Session 1

`terraform apply` prints the values you’ll need next:

```text
workspace_url            = https://adb-XXXXXXXXXXXX.XX.azuredatabricks.net
external_location_url    = abfss://landing@<storage>.dfs.core.windows.net/
landing_path             = abfss://landing@<storage>.dfs.core.windows.net/state-fund-poc
managed_catalog_location = abfss://state-fund-poc-managed@<storage>.dfs.core.windows.net/state_fund_poc
```

Use `landing_path` as the value for the pipelines’ `landing_path` widget — it matches the default in
`common/config.py`. In Session 1 you’ll use `managed_catalog_location` as the catalog’s
`MANAGED LOCATION`. Re‑print the outputs any time with `terraform output`.

### 6. Tear down (when finished)

```powershell
terraform destroy
```

Removes every resource created by this session. Docs:
[terraform destroy](https://developer.hashicorp.com/terraform/cli/commands/destroy).

## Next

Continue to **Session 1 — Foundations & Bronze Ingestion**, which creates the `state_fund_poc`
catalog and schemas and lands the six source files into Bronze.

## References

- [Databricks Terraform provider](https://learn.microsoft.com/azure/databricks/dev-tools/terraform/) ·
  [Deploy a workspace with Terraform](https://learn.microsoft.com/azure/databricks/dev-tools/terraform/azure-workspace)
- [Unity Catalog setup on Azure (Terraform guide)](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/unity-catalog-azure)
- [Connect to an ADLS Gen2 external location](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/external-locations-adls)
- [Use Azure managed identities in Unity Catalog](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities)
