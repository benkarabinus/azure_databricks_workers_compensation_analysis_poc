"""Central configuration for the State Fund Lane 1 POC.

Resolves the Unity Catalog catalog/schema/table names and the ADLS landing
paths from Databricks widgets or job parameters, with sensible defaults so that
helper modules and local scripts can import this module **without** a Spark
session.

Usage in a Databricks notebook::

    from common.config import get_config
    cfg = get_config(dbutils)            # reads widgets if present
    spark.read.table(cfg.table("silver", "claims"))
    landing = cfg.source_path("claims")  # abfss path for Auto Loader

Usage in a plain Python script::

    from common.config import get_config
    cfg = get_config()                   # defaults / environment variables
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

# --------------------------------------------------------------------------- #
# Defaults (override via widgets, job parameters, or environment variables)
# --------------------------------------------------------------------------- #

DEFAULT_CATALOG = "state_fund_poc"

# Raw source files land in a Unity Catalog external volume (best practice for
# ingestion landing zones), created in session-1 over the session-0 `landing`
# external location. Pipelines read from the /Volumes FUSE path below; each
# source has its own subfolder (see source_path).
LANDING_SCHEMA = "bronze"
LANDING_VOLUME = "landing"
DEFAULT_LANDING_PATH = f"/Volumes/{DEFAULT_CATALOG}/{LANDING_SCHEMA}/{LANDING_VOLUME}"

# Schema names (the six UC schemas in the single POC catalog).
SCHEMAS: tuple[str, ...] = ("bronze", "silver", "gold", "config", "security", "ml")

# Bronze tables keyed by logical source name -> (filename, bronze table name).
SOURCE_FILES: dict[str, dict[str, str]] = {
    "claims": {"file": "claims_core.csv", "table": "raw_claims", "format": "csv"},
    "hr": {"file": "hr_records.csv", "table": "raw_hr_records", "format": "csv"},
    "treatments": {"file": "medical_treatments.json", "table": "raw_medical_treatments", "format": "json"},
    "billing": {"file": "provider_billing.json", "table": "raw_provider_billing", "format": "json"},
    "notes": {"file": "adjuster_notes.xlsx", "table": "raw_adjuster_notes", "format": "xlsx"},
    "siu_labels": {"file": "siu_labels.csv", "table": "raw_siu_labels", "format": "csv"},
}

# Registered model names in the `ml` schema.
MODELS: dict[str, str] = {"rtw": "rtw_model", "fraud": "fraud_model"}

# Group granted access to unmasked PII (see session-2 governance).
PII_AUTHORIZED_GROUP = "pii_authorized"


@dataclass(frozen=True)
class Config:
    """Resolved configuration for a run of the POC pipelines."""

    catalog: str = DEFAULT_CATALOG
    landing_path: str = DEFAULT_LANDING_PATH

    def schema(self, layer: str) -> str:
        """Return the fully qualified schema, e.g. ``state_fund_poc.silver``."""
        if layer not in SCHEMAS:
            raise ValueError(f"Unknown schema '{layer}'. Expected one of {SCHEMAS}.")
        return f"{self.catalog}.{layer}"

    def table(self, layer: str, name: str) -> str:
        """Return a three-level table name, e.g. ``state_fund_poc.silver.claims``."""
        return f"{self.schema(layer)}.{name}"

    def model(self, key: str) -> str:
        """Return a registered model name, e.g. ``state_fund_poc.ml.rtw_model``."""
        if key not in MODELS:
            raise ValueError(f"Unknown model '{key}'. Expected one of {tuple(MODELS)}.")
        return f"{self.schema('ml')}.{MODELS[key]}"

    def source_path(self, source: str) -> str:
        """Return the landing folder for a source, e.g. ``<landing>/claims``."""
        if source not in SOURCE_FILES:
            raise ValueError(f"Unknown source '{source}'. Expected one of {tuple(SOURCE_FILES)}.")
        return f"{self.landing_path.rstrip('/')}/{source}"

    def source_file(self, source: str) -> str:
        """Return the file name for a source, e.g. ``claims_core.csv``."""
        return SOURCE_FILES[source]["file"]

    def bronze_table(self, source: str) -> str:
        """Return the Bronze table for a source, e.g. ``state_fund_poc.bronze.raw_claims``."""
        return self.table("bronze", SOURCE_FILES[source]["table"])


def _widget(dbutils, name: str, default: str) -> str:
    """Read a Databricks widget, falling back to an environment variable or default."""
    if dbutils is not None:
        try:
            value = dbutils.widgets.get(name)
            if value:
                return value
        except Exception:
            pass
    return os.environ.get(name.upper(), default)


def get_config(dbutils=None) -> Config:
    """Resolve configuration from widgets / job params / env, with defaults.

    Parameters
    ----------
    dbutils:
        The Databricks ``dbutils`` handle (optional). When provided, the
        ``catalog`` and ``landing_path`` widgets are consulted first.
    """
    catalog = _widget(dbutils, "catalog", DEFAULT_CATALOG)
    default_landing = f"/Volumes/{catalog}/{LANDING_SCHEMA}/{LANDING_VOLUME}"
    landing_path = _widget(dbutils, "landing_path", default_landing)
    return Config(catalog=catalog, landing_path=landing_path)
