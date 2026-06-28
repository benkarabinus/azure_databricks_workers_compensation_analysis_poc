# Databricks notebook source
# MAGIC %md
# MAGIC # Session 5 — Batch score the fraud triage model
# MAGIC
# MAGIC Loads the `@champion` fraud model from Unity Catalog, scores `gold.fraud_features`, and writes
# MAGIC the ranked triage queue `gold.fraud_scores` (`fraud_risk_score`, `risk_tier`,
# MAGIC `top_contributing_factor`). The Databricks App in `app/` reads this table.
# MAGIC
# MAGIC > **POC note:** we score the labeled feature table (which the model also trained on), so the
# MAGIC > demo shows the model surfacing known frauds near the top. In production you'd score **all /
# MAGIC > open** claims with the same feature logic — see the Session 5 README.
# MAGIC >
# MAGIC > **Framing:** the score *ranks* claims for SIU review (triage acceleration); it does not
# MAGIC > auto-decide fraud.
# MAGIC
# MAGIC **Docs:** [Load UC models](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install mlflow[databricks] -q
# MAGIC %restart_python

# COMMAND ----------

import mlflow
import mlflow.sklearn
import numpy as np
from pyspark.sql import functions as F

mlflow.set_registry_uri("databricks-uc")

CATALOG = "state_fund_poc"
MODEL = f"models:/{CATALOG}.ml.fraud_model@champion"
SOURCE_TABLE = f"{CATALOG}.gold.fraud_features"
TARGET_TABLE = f"{CATALOG}.gold.fraud_scores"

model = mlflow.sklearn.load_model(MODEL)
print("Loaded", MODEL)

# COMMAND ----------

pdf = spark.read.table(SOURCE_TABLE).toPandas()
X = pdf.drop(columns=["claim_id", "is_fraud"])
proba = model.predict_proba(X)[:, 1]

pdf["fraud_risk_score"] = proba.round(4)
pdf["risk_tier"] = np.select([proba >= 0.70, proba >= 0.40], ["High", "Medium"], default="Low")


def top_contributing_factor(r):
    """Heuristic 'why' label. A SHAP-based attribution would be the production upgrade."""
    if r["billing_vs_claim_ratio"] is not None and r["billing_vs_claim_ratio"] >= 2:
        return f"billing_vs_claim_ratio={r['billing_vs_claim_ratio']:.2f}"
    if r["provider_claim_count_30d"] >= 20:
        return f"provider_claim_count_30d={int(r['provider_claim_count_30d'])}"
    if r["note_fraud_signal"] == 1:
        return "note_fraud_signal"
    if r["distinct_providers"] >= 4:
        return f"distinct_providers={int(r['distinct_providers'])}"
    if r["attorney_flag"] == 1:
        return "attorney_flag"
    if r["days_injury_to_report"] is not None and r["days_injury_to_report"] >= 10:
        return f"days_injury_to_report={int(r['days_injury_to_report'])}"
    return "none_material"


pdf["top_contributing_factor"] = pdf.apply(top_contributing_factor, axis=1)

out = pdf[["claim_id", "fraud_risk_score", "risk_tier", "top_contributing_factor", "is_fraud"]].rename(
    columns={"is_fraud": "is_fraud_actual"}  # POC-only: lets the demo compare score vs known label
)
sdf = spark.createDataFrame(out).withColumn("scored_at", F.current_timestamp())
sdf.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(TARGET_TABLE)
print(f"Wrote {TARGET_TABLE}: {sdf.count()} rows")

# COMMAND ----------

# Highest-risk claims first — this is the investigator triage queue the app renders.
display(spark.read.table(TARGET_TABLE).orderBy(F.desc("fraud_risk_score")).limit(20))
