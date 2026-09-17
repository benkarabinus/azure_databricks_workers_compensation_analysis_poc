# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # Session 5 — Batch score the RTW duration model
# MAGIC
# MAGIC Loads the `@champion` RTW model from Unity Catalog and scores `gold.rtw_features`, writing
# MAGIC `gold.rtw_predictions` (predicted vs actual `days_to_rtw`). Runs on **Serverless**.
# MAGIC
# MAGIC > **POC note:** we score the closed-claim feature table (which the model also trained on), so
# MAGIC > this is a *predicted-vs-actual* demo, not a true hold-out. In production you'd score **open**
# MAGIC > claims with the same feature logic (no label) — see the Session 5 README.
# MAGIC
# MAGIC **Docs:** [Load UC models](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)
# MAGIC · [mlflow.sklearn](https://mlflow.org/docs/latest/python_api/mlflow.sklearn.html)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install mlflow[databricks] scikit-learn==1.7.2 -q
# MAGIC %restart_python

# COMMAND ----------

import mlflow
import skops.io as sio
import os, yaml
from pyspark.sql import functions as F

# Shim for sklearn 1.6→1.7 compat (_RemainderColsList removed in 1.7)
import sklearn.compose._column_transformer as _ct
class _RemainderColsList(list):
    pass
_ct._RemainderColsList = _RemainderColsList

mlflow.set_registry_uri("databricks-uc")

CATALOG = "state_fund_poc"
MODEL = f"models:/{CATALOG}.ml.rtw_model@champion"
SOURCE_TABLE = f"{CATALOG}.gold.rtw_features"
TARGET_TABLE = f"{CATALOG}.gold.rtw_predictions"

local_path = mlflow.artifacts.download_artifacts(artifact_uri=MODEL)
with open(os.path.join(local_path, "MLmodel")) as f:
    flavor = yaml.safe_load(f)["flavors"]["sklearn"]
model_path = os.path.join(local_path, flavor["pickled_model"])
trusted_types = sio.get_untrusted_types(file=model_path)
model = sio.load(model_path, trusted=trusted_types)
print("Loaded", MODEL)

# COMMAND ----------

pdf = spark.read.table(SOURCE_TABLE).toPandas()
X = pdf.drop(columns=["claim_id", "days_to_rtw"])
pdf["predicted_days_to_rtw"] = model.predict(X).round(1)

out = pdf[["claim_id", "predicted_days_to_rtw", "days_to_rtw"]].rename(
    columns={"days_to_rtw": "actual_days_to_rtw"}
)
sdf = spark.createDataFrame(out).withColumn("scored_at", F.current_timestamp())
sdf.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(TARGET_TABLE)
print(f"Wrote {TARGET_TABLE}: {sdf.count()} rows")

# COMMAND ----------

# Largest predicted durations first (claims a case manager might intervene on early).
display(spark.read.table(TARGET_TABLE).orderBy(F.desc("predicted_days_to_rtw")).limit(20))