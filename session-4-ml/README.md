# Session 4 — Model Training & MLflow

**Goal:** Train the two POC models on the Gold feature tables, track every candidate with MLflow,
and register the best of each to Unity Catalog — all on **Serverless** compute.

**Output:** `state_fund_poc.ml.rtw_model` (RTW duration regression) and
`state_fund_poc.ml.fraud_model` (fraud triage classification), each with a `@champion` alias.

> **Why not AutoML?** Databricks AutoML regression/classification needs a classic Databricks-Runtime-ML
> cluster (it's unsupported on serverless and is being removed in DBR 18.0 ML). To keep the POC 100%
> serverless and future-proof, we train scikit-learn candidate models directly and compare them with
> MLflow — the same outcome (tracked runs + a registered best model), without leaving serverless.

This session is a **notebook walkthrough**: run two training notebooks, then a registration notebook.

## Files in this folder

| File | What it is | How you use it |
| --- | --- | --- |
| [train_rtw_model.py](train_rtw_model.py) | Serverless notebook — RTW regression candidates → MLflow | Import, run on Serverless |
| [train_fraud_model.py](train_fraud_model.py) | Serverless notebook — fraud classification candidates → MLflow | Import, run on Serverless |
| [register_models.py](register_models.py) | Serverless notebook — register best runs to UC + `@champion` | Import, run **after** the two training notebooks |

## Prerequisites

- **Session 3 complete** — `gold.rtw_features` and `gold.fraud_features` exist and are populated.
- **SELECT** on the Gold tables and **CREATE MODEL** on the `state_fund_poc.ml` schema.
- Run all three notebooks as the **same user** — the training experiments are created under
  `/Users/<you>/…` and `register_models.py` looks them up there.

## The models

| Model | Source table | Label | Primary metric | Candidates |
| --- | --- | --- | --- | --- |
| `ml.rtw_model` | `gold.rtw_features` (closed claims) | `days_to_rtw` | **RMSE** (also MAE, R²) | RandomForest, HistGradientBoosting |
| `ml.fraud_model` | `gold.fraud_features` (labeled subset) | `is_fraud` | **PR-AUC** (also ROC-AUC, F1) | RandomForest, HistGradientBoosting, LogisticRegression |

PR-AUC is the fraud metric because the labels are imbalanced (~8–12% positive) — accuracy would be
misleading.

---

## Steps

### 1. Train the RTW duration model

1. **Workspace ▸ ⋮ ▸ Import** [train_rtw_model.py](train_rtw_model.py) (imports as a Python
   notebook).
2. Attach **Serverless** and **Run all**. It loads `gold.rtw_features`, trains the candidate
   regressors, logs each to the MLflow experiment `/Users/<you>/state_fund_poc_rtw`, and prints the
   best by RMSE.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking) ·
[Track scikit-learn models](https://learn.microsoft.com/azure/databricks/mlflow/tracking-ex-scikit)

### 2. Train the fraud triage model

Import [train_fraud_model.py](train_fraud_model.py), attach **Serverless**, **Run all**. It trains
the classifiers on `gold.fraud_features`, logs them to `/Users/<you>/state_fund_poc_fraud`, and
prints the best by **PR-AUC**.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking) ·
[average_precision_score (PR-AUC)](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html)

### 3. Compare runs

Open **Experiments** (left nav) and the two experiments. Sort the RTW runs by `rmse` (ascending) and
the fraud runs by `pr_auc` (descending); inspect params, metrics, and the logged model artifacts.

Docs: [View and compare runs](https://learn.microsoft.com/azure/databricks/mlflow/runs)

### 4. Register the best models to Unity Catalog

Import [register_models.py](register_models.py), attach **Serverless**, **Run all**. It re-derives
the best run per experiment, registers it as `state_fund_poc.ml.rtw_model` /
`state_fund_poc.ml.fraud_model`, assigns the **`@champion`** alias, writes a description, and
validates by loading each `@champion` model and scoring a few rows.

Confirm in **Catalog ▸ `state_fund_poc` ▸ `ml`** that both models exist with a `champion` alias.

Docs: [Models in Unity Catalog](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/) ·
[Model aliases](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/#deploy-models-using-aliases)

---

## Design notes

- **Serverless, no AutoML.** scikit-learn `RandomForest` + `HistGradientBoosting` (built in — no
  extra install) stand in for AutoML's multi-algorithm search; add LightGBM/XGBoost via `%pip` later
  if you want stronger models.
- **Training and registration are separate.** Training only logs/compares; `register_models.py` is
  the promotion step (select best → register → alias) — a clean MLOps boundary.
- **`@champion` alias** is how Session 5 references the serving model, decoupled from version numbers.
- **Fraud framing.** The classifier produces a probability used to **rank** claims for SIU review,
  never to auto-decide fraud.

## Next

Continue to **Session 5 — Serving, App & Orchestration**. See the [Deployment Guide](../DEPLOYMENT_GUIDE.md).
