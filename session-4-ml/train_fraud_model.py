# Databricks notebook source
# MAGIC %md
# MAGIC # Session 4 — Fraud triage model (serverless training + MLflow)
# MAGIC
# MAGIC Trains and compares classification models that score `is_fraud` from `gold.fraud_features`
# MAGIC (the labeled SIU subset), logging every candidate to MLflow. The labels are imbalanced
# MAGIC (~8–12% positive), so the PRIMARY metric is **PR-AUC** (average precision) — accuracy would be
# MAGIC misleading. Runs on **Serverless**.
# MAGIC
# MAGIC **Framing:** this ranks claims for investigator review (triage acceleration); it does **not**
# MAGIC auto-decide fraud. `register_models.py` registers the best run to Unity Catalog.
# MAGIC
# MAGIC **Docs:** [Track training with MLflow](https://learn.microsoft.com/azure/databricks/mlflow/tracking)
# MAGIC · [Log & register models (UC)](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)
# MAGIC · [Imbalanced metrics (PR-AUC)](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install mlflow -q
# MAGIC %restart_python

# COMMAND ----------

import mlflow
import mlflow.sklearn
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier, HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    average_precision_score, roc_auc_score, f1_score, precision_score, recall_score,
)
from mlflow.models.signature import infer_signature

CATALOG = "state_fund_poc"
SOURCE_TABLE = f"{CATALOG}.gold.fraud_features"
LABEL = "is_fraud"

current_user = spark.sql("SELECT current_user()").collect()[0][0]
EXPERIMENT = f"/Users/{current_user}/state_fund_poc_fraud"
mlflow.set_experiment(EXPERIMENT)
print("Tracking to experiment:", EXPERIMENT)

# COMMAND ----------

pdf = spark.read.table(SOURCE_TABLE).toPandas()
pdf = pdf.dropna(subset=[LABEL])
print("rows:", len(pdf), "| positive rate:", round(pdf[LABEL].mean(), 3))

X = pdf.drop(columns=["claim_id", LABEL])
y = pdf[LABEL].astype(int)

# fraud_features is all-numeric (0/1 flags + ratios/counts).
NUMERIC = list(X.columns)
preprocess = ColumnTransformer(
    transformers=[
        ("num", Pipeline([
            ("impute", SimpleImputer(strategy="median")),
            ("scale", StandardScaler()),
        ]), NUMERIC),
    ]
)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# COMMAND ----------

candidates = {
    "random_forest": RandomForestClassifier(
        n_estimators=300, class_weight="balanced", random_state=42, n_jobs=-1),
    "hist_gradient_boosting": HistGradientBoostingClassifier(random_state=42),
    "logistic_regression": LogisticRegression(class_weight="balanced", max_iter=1000),
}

results = []
for name, estimator in candidates.items():
    with mlflow.start_run(run_name=name) as run:
        pipe = Pipeline([("preprocess", preprocess), ("model", estimator)])
        pipe.fit(X_train, y_train)
        proba = pipe.predict_proba(X_test)[:, 1]
        pred = (proba >= 0.5).astype(int)

        pr_auc = average_precision_score(y_test, proba)
        roc_auc = roc_auc_score(y_test, proba)
        f1 = f1_score(y_test, pred, zero_division=0)
        precision = precision_score(y_test, pred, zero_division=0)
        recall = recall_score(y_test, pred, zero_division=0)

        mlflow.log_param("model_type", name)
        mlflow.log_metric("pr_auc", pr_auc)
        mlflow.log_metric("roc_auc", roc_auc)
        mlflow.log_metric("f1", f1)
        mlflow.log_metric("precision", precision)
        mlflow.log_metric("recall", recall)
        _input_ex = X_test.head(3).copy()
        for _c in _input_ex.select_dtypes(include="object"):
            try:
                _input_ex[_c] = pd.to_numeric(_input_ex[_c])
            except (ValueError, TypeError):
                pass
        mlflow.sklearn.log_model(
            pipe, "model",
            signature=infer_signature(X_test, proba),
            input_example=_input_ex,
            skops_trusted_types=["numpy.dtype"],
        )

        results.append((name, pr_auc, roc_auc, run.info.run_id))
        print(f"{name:24} PR-AUC={pr_auc:6.3f}  ROC-AUC={roc_auc:6.3f}  F1={f1:6.3f}")

# COMMAND ----------

# Best by highest PR-AUC. register_models.py re-derives this from the experiment.
results.sort(key=lambda r: r[1], reverse=True)
best = results[0]
print(f"Best model: {best[0]}  (PR-AUC={best[1]:.3f}, run_id={best[3]})")
print("Next: run register_models.py to register the best run to state_fund_poc.ml.fraud_model.")
