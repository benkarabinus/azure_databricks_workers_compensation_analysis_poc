---
title: Session 4 — ML
layout: default
nav_order: 7
---

# Session 4 — Model Training & MLflow

**Goal:** Train the two POC models on the Gold feature tables, track every candidate with MLflow,
and register the best of each to Unity Catalog — all on **Serverless** compute.

**Output:** `state_fund_poc.ml.rtw_model` (RTW duration regression) and
`state_fund_poc.ml.fraud_model` (fraud triage classification), each with a `@champion` alias.

> **Why not AutoML?** Databricks AutoML regression/classification needs a classic
> Databricks-Runtime-ML cluster (unsupported on serverless, and being removed in DBR 18.0 ML). To
> keep the POC 100% serverless, we train scikit-learn candidates directly and compare them with
> MLflow — same outcome (tracked runs + a registered best model) without leaving serverless.

All assets live under `session-4-ml/`. You run two training notebooks, then a registration notebook.

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

PR-AUC is the fraud metric because the labels are imbalanced (~8–12% positive).

## Prerequisites

- **Session 3 complete** — `gold.rtw_features` and `gold.fraud_features` exist.
- **SELECT** on the Gold tables and **CREATE MODEL** on `state_fund_poc.ml`.
- Run all three notebooks as the **same user** (experiments live under `/Users/<you>/…`).

---

## Steps

### 1. Train the RTW duration model

Import `train_rtw_model.py`, attach **Serverless**, **Run all**. It trains the candidate regressors
on `gold.rtw_features`, logs each to `/Users/<you>/state_fund_poc_rtw`, and prints the best by RMSE.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking)

### 2. Train the fraud triage model

Import `train_fraud_model.py`, attach **Serverless**, **Run all**. It trains the classifiers on
`gold.fraud_features`, logs them to `/Users/<you>/state_fund_poc_fraud`, and prints the best by
**PR-AUC**.

Docs: [MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking) ·
[PR-AUC](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html)

### 3. Compare runs

Open **Experiments** and sort RTW runs by `rmse` (asc) and fraud runs by `pr_auc` (desc); inspect
params, metrics, and the logged model artifacts.

Docs: [View and compare runs](https://learn.microsoft.com/azure/databricks/mlflow/runs)

### 4. Register the best models to Unity Catalog

Import `register_models.py`, attach **Serverless**, **Run all**. It registers the best run per
experiment as `ml.rtw_model` / `ml.fraud_model`, assigns the **`@champion`** alias, and validates by
loading each model and scoring a few rows. Confirm in **Catalog ▸ `ml`**.

Docs: [Models in Unity Catalog](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/) ·
[Model aliases](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/#deploy-models-using-aliases)

---

## Design notes

- **Serverless, no AutoML.** scikit-learn `RandomForest` + `HistGradientBoosting` (built in) stand in
  for AutoML's multi-algorithm search; add LightGBM/XGBoost via `%pip` later for stronger models.
- **Training and registration are separate** — a clean MLOps boundary (compare, then promote).
- **`@champion` alias** is how Session 5 references the serving model, decoupled from versions.
- **Fraud framing** — the classifier ranks claims for SIU review, never auto-decides fraud.

## Next

Continue to **Session 5 — Serving, App & Orchestration**.
