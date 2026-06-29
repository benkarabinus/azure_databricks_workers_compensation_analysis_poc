---
title: Session 4 — ML
layout: default
nav_order: 7
---

# Session 4 — Model Training & MLflow

**Goal:** Train the two POC models on the Gold feature tables, track every candidate with MLflow,
and register the best of each to Unity Catalog.

**Output:** `state_fund_poc.ml.rtw_model` (RTW duration regression) and
`state_fund_poc.ml.fraud_model` (fraud triage classification), each with a `@champion` alias for easy model selection update in automated pipelines.

All assets live under `session-4-ml/`. You run two training notebooks to identify the best candidate algorithms, then a registration notebook to register the top candidates for each use case.

## Source files

| File | What it is | How you use it |
| --- | --- | --- |
| `train_rtw_model.py` | Serverless notebook — RTW regression candidates → MLflow | Import, run on Serverless |
| `train_fraud_model.py` | Serverless notebook — fraud classification candidates → MLflow | Import, run on Serverless |
| `register_models.py` | Serverless notebook — register best runs to UC + `@champion` | Run after the training notebooks |

## The models

| Model | Source table | Label | Primary metric | Candidates |
| --- | --- | --- | --- | --- |
| `ml.rtw_model` | `gold.rtw_features` (closed claims) | `days_to_rtw` | **RMSE** (+ MAE, R²) | RandomForest, HistGradientBoosting |
| `ml.fraud_model` | `gold.fraud_features` (labeled subset) | `is_fraud` | **PR-AUC** (+ ROC-AUC, F1) | RandomForest, HistGradientBoosting, LogisticRegression |

PR-AUC is the fraud scoring metric because the labels are imbalanced (~8–12% positive).

## Prerequisites

- **Session 3 complete** — `gold.rtw_features` and `gold.fraud_features` exist.
- **SELECT** on the Gold tables and **CREATE MODEL** on `state_fund_poc.ml` schema.
- Run all three notebooks as the **same user** (experiments live under `/Users/<you>/…`) in the workspace directory.

---

## Steps

### 1. Train the RTW duration model

1. Import `train_rtw_model.py`.
2. Attach to **Serverless** compute.
3. Run all cells in the notebook. This trains the candidate regressors on `gold.rtw_features`, logs each to `/Users/<you>/state_fund_poc_rtw`, and prints the best by RMSE.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking)

### 2. Train the fraud triage model

1. Import `train_fraud_model.py`.
2. Attach to **Serverless** compute.
3. Run all cells in the notebook. This trains the classifiers on `gold.fraud_features`, logs them to `/Users/<you>/state_fund_poc_fraud`, and prints the best by **PR-AUC**.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking) ·
[PR-AUC](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html)

### 3. Compare runs

Open **Experiments** in the Azure Databricks UI and sort RTW runs by `rmse` (asc) and fraud runs by `pr_auc` (desc). Inspect the results for each candidate algorithm.

Docs: [View and compare runs](https://learn.microsoft.com/azure/databricks/mlflow/runs)

### 4. Register the best models to Unity Catalog

1. Import `register_models.py`.
2. Attach to **Serverless** compute.
3. Run all cells in the notebook. This registers the best run per experiment as `ml.rtw_model` / `ml.fraud_model`, assigns the **`@champion`** alias, and validates by loading each model and scoring a few rows.
4. Confirm the models show in **Catalog ▸ `ml`**.

Docs: [Models in Unity Catalog](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/) ·
[Model aliases](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/#deploy-models-using-aliases)

---

## Design notes

- **Serverless** scikit-learn `RandomForest` + `HistGradientBoosting.` Add LightGBM/XGBoost via `%pip` later for stronger models.
- **Training and registration are separate** — a clean MLOps boundary (compare, then promote).
- **`@champion` alias** is how Session 5 references the serving model, decoupled from versions.
- **Fraud framing** — the classifier ranks claims for SIU review, does not automatically determine fraud in this example.

## Next

Continue to **Session 5 — Serving, App & Orchestration**.
