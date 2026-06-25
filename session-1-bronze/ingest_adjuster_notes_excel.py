# Databricks notebook source
# =============================================================================
# Session 1 - Bronze Excel ingestion: adjuster_notes.xlsx -> bronze.raw_adjuster_notes
#
# Auto Loader does not support .xlsx, so the adjuster notes are read with
# openpyxl (via pandas) from the raw-landing volume and written as a Delta table.
# Run this as a Serverless Jobs notebook task (see the session README).
#
# The table is OVERWRITTEN each run: the single small workbook is the whole
# source, so a full replace keeps the notebook idempotent (re-runs never
# duplicate rows). Values are read as strings to keep Bronze as-landed.
# =============================================================================

# COMMAND ----------
# MAGIC %pip install openpyxl
# COMMAND ----------
# Restart Python so the freshly installed library is importable (serverless).
dbutils.library.restartPython()

# COMMAND ----------
import pandas as pd
from pyspark.sql.functions import current_timestamp, lit

CATALOG = "state_fund_poc"
LANDING = f"/Volumes/{CATALOG}/bronze/landing"
SOURCE_FILE = f"{LANDING}/notes/adjuster_notes.xlsx"
TARGET_TABLE = f"{CATALOG}.bronze.raw_adjuster_notes"

# COMMAND ----------
# Read every column as text (Bronze keeps values exactly as landed) and turn
# pandas NaNs into proper nulls before handing off to Spark.
pdf = pd.read_excel(SOURCE_FILE, engine="openpyxl", dtype=str)
pdf = pdf.where(pd.notnull(pdf), None)

# COMMAND ----------
df = (
    spark.createDataFrame(pdf)
    .withColumn("_source_file", lit(SOURCE_FILE))
    .withColumn("_ingested_at", current_timestamp())
)

(
    df.write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(TARGET_TABLE)
)

print(f"Wrote {df.count()} rows to {TARGET_TABLE}")
