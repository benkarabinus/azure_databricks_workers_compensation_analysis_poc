---
title: Session 5 — Serving
layout: default
nav_order: 8
---

# Session 5 — Serving, Triage App, Orchestration & Governance

**Goal:** Operationalize the models — batch-score to Gold, build the investigator triage app with
Vector Search, orchestrate the whole medallion end-to-end, and verify governance.

**Output:** `gold.fraud_scores` (ranked triage queue) + `gold.rtw_predictions`, a Vector Search
index, a live Streamlit **Databricks App**, an end-to-end **Workflow**, and governance validation.

![Fraud triage serving flow — features + @champion model → batch score → gold.fraud_scores → Databricks App, with Vector Search similar-claim lookup](diagrams/fraud-triage-flow.svg)

All assets live in the GitHub repo directory under `session-5-serving/`: scoring notebooks, a Vector Search notebook, a deployed
App, a Workflow YAML, and interactive governance SQL.

## Source files

| File | What it is |
| --- | --- |
| `batch_score_fraud.py` | Score `@champion` fraud model → `gold.fraud_scores` (ranked queue) |
| `batch_score_rtw.py` | Score `@champion` RTW model → `gold.rtw_predictions` |
| `vector_search_setup.py` | AI Search index over redacted notes (similar-claim lookup) |
| `app/` | Streamlit Databricks App (reads `gold.fraud_scores`) |
| `workflow/end_to_end_job.yaml` | Reference Workflow: ingest → DLT → score → quality |
| `governance/` | `audit_system_tables.sql`, `row_filter_demo.sql`, `time_travel_recovery.sql` |

## Prerequisites

- **Session 4 complete** — `ml.rtw_model` and `ml.fraud_model` exist with a `@champion` alias.
- **Vector Search / AI Search** available in your region + the `databricks-gte-large-en` embedding
  endpoint.
- For the App: a **SQL warehouse** to attach as a resource, and the app's service principal granted
  `SELECT` on `gold.fraud_scores`.

> **POC scoring note:** we score the existing Gold feature tables (which the models also trained on)
> — a predicted-vs-actual demo. In production you'd score open/unlabeled claims by reusing the Gold
> feature SQL without the label join / closed filter.

---

## Steps

### 1. Score the fraud model → triage queue

1. Import `batch_score_fraud.py`.
2. Run all cells in the notebook. This loads `ml.fraud_model@champion`, scores `gold.fraud_features`, and writes the ranked **`gold.fraud_scores`** (`fraud_risk_score`, `risk_tier`, `top_contributing_factor`).

### 2. Score the RTW model → predictions

1. Import `batch_score_rtw.py`.
2. Run all cells in the notebook. This writes `gold.rtw_predictions` (predicted vs actual `days_to_rtw`).

### 3. Build the Vector Search index

1. Import `vector_search_setup.py`.
2. Run cell by cell (the endpoint takes a few minutes to come ONLINE). It creates a change data feed (CDF) source table from the redacted notes, an AI Search endpoint, a delta-sync index, and runs a similarity query.

Docs: [Create AI Search endpoints and indexes](https://learn.microsoft.com/azure/databricks/ai-search/create-ai-search)

### 4. Deploy the triage app

1. In the Azure Databricks UI navigate to **Compute ▸ Apps ▸ Create app** (Streamlit).
2. Add a **SQL warehouse** resource keyed `sql-warehouse`.
3. Upload source code in the `app` folder in the GitHub repo directory and click **Deploy**.
4. Grant the app's service principal `SELECT` on `gold.fraud_scores`.

Docs: [Databricks Apps](https://learn.microsoft.com/azure/databricks/dev-tools/databricks-apps/)

### 5. Orchestrate end-to-end

1. Edit `workflow/end_to_end_job.yaml` in the GitHub repo directory. (replace the `<...>` pipeline IDs / notebook paths) with the IDs and paths to pipelines and notebooks you created in previous sessions.
2. Create a job and paste the updated .yaml file text via the kebab (**...**) ▸ **Edit as YAML*.
3. Double check that all pipeline IDs and notebook paths are correct.
3. Run the workflow. It — chains **ingest → Bronze → Silver → Gold → score → quality** into a single Azure Databricks job run on serverless compute.

Docs: [Lakeflow Jobs](https://learn.microsoft.com/azure/databricks/jobs/)

### 6. Verify governance

Run the three `governance/` notebooks:

1. `row_filter_demo.sql` — masks/row filter.
2. `audit_system_tables.sql` — access + lineage (needs `system.access` enabled).
3. `time_travel_recovery.sql` — Delta history + `RESTORE`.

Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) ·
[System tables](https://learn.microsoft.com/azure/databricks/admin/system-tables/) ·
[Delta history](https://learn.microsoft.com/azure/databricks/delta/history)

---

## Design notes

- **`@champion` indirection** — scoring loads `models:/…@champion.` Re-registering a better model
  changes what serves predictions with no code changes.
- **App reads Gold only** — the Streamlit app queries `gold.fraud_scores` via a SQL warehouse under
  its service principal, never raw/PII tables.
- **Vector Search on redacted text** — the index embeds `note_text_redacted` (PII removed in Session
  2).
- **Fraud = triage acceleration** — the queue ranks claims for SIU review. Fraud is not "automatically predicted" for the purpose of this tutorial. In this scenario a human stays in the loop.

This completes the POC build!
