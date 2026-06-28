---
title: Session 5 — Serving
layout: default
nav_order: 8
---

# Session 5 — Serving, Triage App, Orchestration & Governance

**Goal:** Operationalize the models — batch-score to Gold, build the investigator triage app with
Vector Search, orchestrate the whole medallion end-to-end, and verify governance.

**Output:** `gold.fraud_scores` (ranked triage queue) + `gold.rtw_predictions`, a Vector Search
index, a live Streamlit **Databricks App**, an end-to-end **Workflow**, and governance demos.

All assets live under `session-5-serving/`: scoring notebooks, a Vector Search notebook, a deployed
App, a Workflow JSON, and interactive governance SQL.

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

Import `batch_score_fraud.py`, **Run all** on Serverless — loads `ml.fraud_model@champion`, scores
`gold.fraud_features`, writes the ranked **`gold.fraud_scores`** (`fraud_risk_score`, `risk_tier`,
`top_contributing_factor`).

### 2. Score the RTW model → predictions

Import `batch_score_rtw.py`, **Run all** — writes `gold.rtw_predictions` (predicted vs actual
`days_to_rtw`).

### 3. Build the Vector Search index

Import `vector_search_setup.py`, run cell by cell (the endpoint takes a few minutes to come ONLINE).
It creates a CDF source table from the redacted notes, an AI Search endpoint, a delta-sync index, and
runs a similarity query.

Docs: [Create AI Search endpoints and indexes](https://learn.microsoft.com/azure/databricks/ai-search/create-ai-search)

### 4. Deploy the triage app

**Compute ▸ Apps ▸ Create app** (Streamlit), add a **SQL warehouse** resource keyed `sql-warehouse`,
upload `app/`, **Deploy**, and grant the app's service principal `SELECT` on `gold.fraud_scores`.

Docs: [Databricks Apps](https://learn.microsoft.com/azure/databricks/dev-tools/databricks-apps/)

### 5. Orchestrate end-to-end

Edit `workflow/end_to_end_job.yaml` (replace the `<...>` pipeline IDs / notebook paths), then create
a job and paste it via the kebab (**...**) ▸ **Edit as YAML** (the Jobs UI imports YAML, not JSON) —
chains **ingest → Bronze → Silver → Gold → score → quality** on Serverless.

Docs: [Lakeflow Jobs](https://learn.microsoft.com/azure/databricks/jobs/)

### 6. Verify governance

Run the three `governance/` notebooks: `row_filter_demo.sql` (masks/row filter), `audit_system_tables.sql`
(access + lineage, needs `system.access` enabled), `time_travel_recovery.sql` (Delta history +
`RESTORE`).

Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) ·
[System tables](https://learn.microsoft.com/azure/databricks/admin/system-tables/) ·
[Delta history](https://learn.microsoft.com/azure/databricks/delta/history)

---

## Design notes

- **`@champion` indirection** — scoring loads `models:/…@champion`; re-registering a better model
  changes what serves with no code change.
- **App reads Gold only** — the Streamlit app queries `gold.fraud_scores` via a SQL warehouse under
  its service principal, never raw/PII tables.
- **Vector Search on redacted text** — the index embeds `note_text_redacted` (PII removed in Session
  2).
- **Fraud = triage acceleration** — the queue ranks claims for SIU review, never auto-decides fraud.

This completes the POC build.
