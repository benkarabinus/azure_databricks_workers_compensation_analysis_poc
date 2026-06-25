# Input variables for Session 0. Copy terraform.tfvars.example to
# terraform.tfvars and adjust values to suit your environment.

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription ID. If null, the ARM_SUBSCRIPTION_ID environment variable is used."
}

variable "prefix" {
  type        = string
  default     = "sfpoc"
  description = "Short lowercase prefix for resource names (State Fund POC)."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase alphanumeric characters."
  }
}

variable "location" {
  type        = string
  default     = "westus2"
  description = "Azure region. Must support Databricks serverless compute. See https://learn.microsoft.com/azure/databricks/resources/feature-region-support"
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "When true, Terraform creates the resource group. When false, an existing group named resource_group_name is reused (create-if-not-exists pattern)."
}

variable "resource_group_name" {
  type        = string
  default     = "rg-state-fund-poc"
  description = "Name of the resource group to create or reuse."
}

variable "landing_container" {
  type        = string
  default     = "landing"
  description = "ADLS Gen2 container registered as the landing external location (raw source files; Session 1 ingest)."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", var.landing_container))
    error_message = "Container names must be 3-63 chars, lowercase letters/numbers/hyphens only (no uppercase or underscores)."
  }
}

variable "managed_container" {
  type        = string
  default     = "state-fund-poc-managed"
  description = "ADLS Gen2 container that backs Unity Catalog catalog-level managed storage (Bronze/Silver/Gold managed tables)."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", var.managed_container))
    error_message = "Container names must be 3-63 chars, lowercase letters/numbers/hyphens only (no uppercase or underscores)."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Storage account name (3-24 lowercase alphanumeric, globally unique)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "workspace_name" {
  type        = string
  description = "Databricks workspace name."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{3,64}$", var.workspace_name))
    error_message = "workspace_name must be 3-64 characters: letters, digits, hyphens, or underscores."
  }
}

variable "access_connector_name" {
  type        = string
  description = "Name of the Azure Databricks access connector (managed identity)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,64}$", var.access_connector_name))
    error_message = "access_connector_name must be 3-64 characters: letters, digits, hyphens, underscores, or periods."
  }
}

variable "tags" {
  type = map(string)
  default = {
    project = "state-fund-lane1-poc"
    env     = "poc"
  }
  description = "Tags applied to all resources."
}
