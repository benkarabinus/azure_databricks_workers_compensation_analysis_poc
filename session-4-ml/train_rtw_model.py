# Databricks notebook source
# MAGIC %md
# MAGIC # Session 4 — Return-to-Work duration model (serverless training + MLflow)
# MAGIC
# MAGIC Trains and compares regression models that predict `days_to_rtw` from `gold.rtw_features`,
# MAGIC logging every candidate to MLflow so you can compare runs by RMSE / MAE. This runs on
# MAGIC **Serverless** compute (no classic ML cluster): we train scikit-learn models directly and
# MAGIC track them with MLflow. `register_models.py` then picks the best run and registers it to
# MAGIC Unity Catalog.
# MAGIC
# MAGIC **Why not AutoML?** Databricks AutoML regression/classification requires a classic
# MAGIC Databricks-Runtime-ML cluster (unsupported on serverless and being removed in DBR 18.0 ML).
# MAGIC This notebook keeps the POC 100% serverless.
# MAGIC
# MAGIC **Docs:** [Track training with MLflow](https://learn.microsoft.com/azure/databricks/mlflow/tracking)
# MAGIC · [Log & register models (UC)](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)
# MAGIC · [scikit-learn flavor](https://mlflow.org/docs/latest/python_api/mlflow.sklearn.html)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install mlflow -q
# MAGIC %restart_python

# COMMAND ----------

import mlflow
import mlflow.sklearn
import pandas as pd
from math import sqrt
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder
from sklearn.ensemble import RandomForestRegressor, HistGradientBoostingRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
from mlflow.models.signature import infer_signature

CATALOG = "state_fund_poc"
SOURCE_TABLE = f"{CATALOG}.gold.rtw_features"
LABEL = "days_to_rtw"

# Per-user experiment path so register_models.py can find these runs deterministically.
current_user = spark.sql("SELECT current_user()").collect()[0][0]
EXPERIMENT = f"/Users/{current_user}/state_fund_poc_rtw"
mlflow.set_experiment(EXPERIMENT)
print("Tracking to experiment:", EXPERIMENT)

# COMMAND ----------

# Load the Gold feature table (closed claims only -> label always present).
pdf = spark.read.table(SOURCE_TABLE).toPandas()
pdf = pdf.dropna(subset=[LABEL])
print("rows:", len(pdf))

X = pdf.drop(columns=["claim_id", LABEL])
y = pdf[LABEL].astype(float)

CATEGORICAL = ["injury_type", "body_part", "age_band", "job_class", "wage_band", "provider_specialty", "region"]
NUMERIC = [c for c in X.columns if c not in CATEGORICAL]

preprocess = ColumnTransformer(
    transformers=[
        ("cat", Pipeline([
            ("impute", SimpleImputer(strategy="most_frequent")),
            ("onehot", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
        ]), CATEGORICAL),
        ("num", SimpleImputer(strategy="median"), NUMERIC),
    ]
)

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# COMMAND ----------

# DBTITLE 1,Cell 5
# Candidate algorithms (mirrors AutoML's "try several models" idea, on serverless).
candidates = {
    "random_forest": RandomForestRegressor(n_estimators=300, random_state=42, n_jobs=-1),
    "hist_gradient_boosting": HistGradientBoostingRegressor(random_state=42),
}

results = []
for name, estimator in candidates.items():
    with mlflow.start_run(run_name=name) as run:
        pipe = Pipeline([("preprocess", preprocess), ("model", estimator)])
        pipe.fit(X_train, y_train)
        pred = pipe.predict(X_test)

        rmse = sqrt(mean_squared_error(y_test, pred))
        mae = mean_absolute_error(y_test, pred)
        r2 = r2_score(y_test, pred)

        mlflow.log_param("model_type", name)
        mlflow.log_metric("rmse", rmse)
        mlflow.log_metric("mae", mae)
        mlflow.log_metric("r2", r2)
        _input_ex = X_test.head(3).copy()
        for _c in _input_ex.select_dtypes(include="object"):
            try:
                _input_ex[_c] = pd.to_numeric(_input_ex[_c])
            except (ValueError, TypeError):
                pass
        mlflow.sklearn.log_model(
            pipe, "model",
            signature=infer_signature(X_test, pred),
            input_example=_input_ex,
            skops_trusted_types=["numpy.dtype"],
        )

        results.append((name, rmse, mae, r2, run.info.run_id))
        print(f"{name:24} RMSE={rmse:7.2f}  MAE={mae:7.2f}  R2={r2:6.3f}")

# COMMAND ----------

# Best by lowest RMSE. register_models.py re-derives this from the experiment.
results.sort(key=lambda r: r[1])
best = results[0]
print(f"Best model: {best[0]}  (RMSE={best[1]:.2f}, run_id={best[4]})")
print("Next: run register_models.py to register the best run to state_fund_poc.ml.rtw_model.")
