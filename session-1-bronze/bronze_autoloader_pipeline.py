# Databricks notebook source
# =============================================================================
# Session 1 - Bronze Auto Loader pipeline (Lakeflow Declarative Pipelines / DLT).
#
# Lands the five CSV/JSON sources into bronze.raw_* streaming tables, exactly
# as they arrive, adding only `_source_file` and `_ingested_at`. Nested JSON
# arrays are kept intact; no cleaning happens here (that is Silver's job).
#
# How to run: attach this notebook to a Serverless Lakeflow pipeline whose
# target catalog is `state_fund_poc` and target schema is `bronze` (see the
# session README). The `adjuster_notes.xlsx` source is handled separately by
# ingest_adjuster_notes_excel.py because Auto Loader does not support .xlsx.
# =============================================================================

# COMMAND ----------

import dlt
from pyspark.sql.functions import col, current_timestamp

# COMMAND ----------

# Root of the raw-landing external volume created in 00_create_catalog_and_schemas.sql.
# Override per-pipeline via the `landing_path` configuration if your catalog differs.
LANDING = spark.conf.get("landing_path", "/Volumes/state_fund_poc/bronze/landing")

# (table_name, landing subfolder, file format, reader options)
SOURCES = [
    ("raw_claims", "claims", "csv", {"header": "true"}),
    ("raw_hr_records", "hr", "csv", {"header": "true"}),
    ("raw_siu_labels", "siu_labels", "csv", {"header": "true"}),
    ("raw_medical_treatments", "treatments", "json", {}),
    ("raw_provider_billing", "billing", "json", {}),
]

# COMMAND ----------


def _read_stream(subfolder: str, fmt: str, options: dict):
    """Auto Loader (cloudFiles) stream for one source folder, with lineage columns.

    CSV is read as all-strings (Bronze keeps values as-landed, including the dirty
    patterns); JSON has its nested structure inferred and preserved. DLT manages
    the schema location and checkpoint automatically.
    """
    reader = spark.readStream.format("cloudFiles").option("cloudFiles.format", fmt)
    for key, value in options.items():
        reader = reader.option(key, value)
    return (
        reader.load(f"{LANDING}/{subfolder}")
        .withColumn("_source_file", col("_metadata.file_path"))
        .withColumn("_ingested_at", current_timestamp())
    )


def _define_table(table_name: str, subfolder: str, fmt: str, options: dict):
    @dlt.table(
        name=table_name,
        comment=f"Raw {subfolder} source ({fmt}), as landed.",
        table_properties={"quality": "bronze"},
    )
    def _table():
        return _read_stream(subfolder, fmt, options)

    return _table


# COMMAND ----------

# Register one streaming table per source.
for _name, _subfolder, _fmt, _options in SOURCES:
    _define_table(_name, _subfolder, _fmt, _options)
