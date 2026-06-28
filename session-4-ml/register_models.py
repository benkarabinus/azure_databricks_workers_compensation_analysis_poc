# Databricks notebook source
# MAGIC %md
# MAGIC # Session 4 — Register best models to Unity Catalog
# MAGIC
# MAGIC Picks the best run from each training experiment (lowest RMSE for RTW, highest PR-AUC for
# MAGIC fraud), registers it as a Unity Catalog model, assigns the `@champion` alias, and validates by
# MAGIC loading the model and scoring a few rows.
# MAGIC
# MAGIC Run this **after** `train_rtw_model.py` and `train_fraud_model.py`, as the **same user** (the
# MAGIC experiments are under `/Users/<you>/…`). Requires **CREATE MODEL** on the `state_fund_poc.ml`
# MAGIC schema.
# MAGIC
# MAGIC **Docs:** [Models in Unity Catalog](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)
# MAGIC · [Model aliases](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/#deploy-models-using-aliases)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install mlflow -q
# MAGIC %restart_python

# COMMAND ----------

import mlflow
import mlflow.pyfunc
from mlflow import MlflowClient

# Register into Unity Catalog (three-level model names).
mlflow.set_registry_uri("databricks-uc")
client = MlflowClient(registry_uri="databricks-uc")

CATALOG = "state_fund_poc"
current_user = spark.sql("SELECT current_user()").collect()[0][0]

SPECS = [
    {
        "experiment": f"/Users/{current_user}/state_fund_poc_rtw",
        "metric": "rmse", "ascending": True,
        "model": f"{CATALOG}.ml.rtw_model",
        "table": f"{CATALOG}.gold.rtw_features", "label": "days_to_rtw",
    },
    {
        "experiment": f"/Users/{current_user}/state_fund_poc_fraud",
        "metric": "pr_auc", "ascending": False,
        "model": f"{CATALOG}.ml.fraud_model",
        "table": f"{CATALOG}.gold.fraud_features", "label": "is_fraud",
    },
]

# COMMAND ----------

for s in SPECS:
    experiment = mlflow.get_experiment_by_name(s["experiment"])
    if experiment is None:
        raise ValueError(f"Experiment not found: {s['experiment']} (run the training notebook first).")

    order = f"metrics.{s['metric']} {'ASC' if s['ascending'] else 'DESC'}"
    runs = mlflow.search_runs(experiment_ids=[experiment.experiment_id], order_by=[order], max_results=1)
    if runs.empty:
        raise ValueError(f"No runs found in {s['experiment']}.")

    best_run_id = runs.iloc[0]["run_id"]
    best_metric = runs.iloc[0][f"metrics.{s['metric']}"]

    version = mlflow.register_model(f"runs:/{best_run_id}/model", s["model"])
    client.set_registered_model_alias(s["model"], "champion", version.version)
    client.update_model_version(
        s["model"], version.version,
        description=f"Best {s['metric']} = {best_metric:.4f} (run {best_run_id}).",
    )
    print(f"Registered {s['model']} v{version.version}  {s['metric']}={best_metric:.4f}  -> @champion")

# COMMAND ----------

# Validate: load each @champion model and score a few rows from its Gold table.
for s in SPECS:
    model = mlflow.pyfunc.load_model(f"models:/{s['model']}@champion")
    sample = (
        spark.read.table(s["table"]).limit(5).toPandas()
        .drop(columns=["claim_id", s["label"]])
    )
    print(f"{s['model']}@champion predictions:", list(model.predict(sample)))
