# Session 5 — Serving, Triage App, Orchestration & Governance

**Goal:** Operationalize the models — batch-score to Gold, build the investigator triage app with
Vector Search, orchestrate the whole medallion end-to-end, and verify governance.

**Output:** `gold.fraud_scores` (ranked triage queue) + `gold.rtw_predictions`, a Vector Search
index, a live Streamlit **Databricks App**, an end-to-end **Workflow**, and governance demos
(audit, row filter, time travel).

This session is a **mixed walkthrough**: notebooks (scoring, Vector Search), a deployed App, a
Workflow JSON, and interactive governance SQL.

## Files in this folder

| File | What it is | How you use it |
| --- | --- | --- |
| [batch_score_fraud.py](batch_score_fraud.py) | Serverless notebook — score `@champion` fraud model → `gold.fraud_scores` | Import, run on Serverless |
| [batch_score_rtw.py](batch_score_rtw.py) | Serverless notebook — score `@champion` RTW model → `gold.rtw_predictions` | Import, run on Serverless |
| [vector_search_setup.py](vector_search_setup.py) | Serverless notebook — AI Search index over redacted notes | Import, run on Serverless |
| [app/app.py](app/app.py) · [app/app.yaml](app/app.yaml) · [app/requirements.txt](app/requirements.txt) | Streamlit **Databricks App** (reads `gold.fraud_scores`) | Deploy as a Databricks App |
| [workflow/end_to_end_job.json](workflow/end_to_end_job.json) | Reference Workflow: ingest → DLT → score → quality | Adapt placeholders, import as a Job |
| [governance/](governance/) | `audit_system_tables.sql`, `row_filter_demo.sql`, `time_travel_recovery.sql` | Import as notebooks, run |

## Prerequisites

- **Session 4 complete** — `state_fund_poc.ml.rtw_model` and `ml.fraud_model` exist with a
  `@champion` alias.
- **`SELECT`/`MODIFY`** on the Gold schema (scoring writes `gold.fraud_scores` / `gold.rtw_predictions`).
- **Vector Search / AI Search** available in your region, plus the `databricks-gte-large-en`
  embedding endpoint.
- For the App: a **SQL warehouse** to attach as a resource, and the app's service principal granted
  `SELECT` on `gold.fraud_scores`.

> **POC scoring note:** we score the existing Gold feature tables (`fraud_features` = labeled subset,
> `rtw_features` = closed claims), which the models also trained on — a *predicted-vs-actual* demo,
> not a true hold-out. In production you'd score **open/unlabeled** claims by reusing the same Gold
> feature SQL without the label join / closed filter.

---

## Steps

### 1. Score the fraud model → triage queue

Import [batch_score_fraud.py](batch_score_fraud.py), attach **Serverless**, **Run all**. It loads
`ml.fraud_model@champion`, scores `gold.fraud_features`, derives `risk_tier` + a heuristic
`top_contributing_factor`, and writes the ranked **`gold.fraud_scores`**.

Docs: [Load UC models](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/)

### 2. Score the RTW model → predictions

Import [batch_score_rtw.py](batch_score_rtw.py), **Run all** — writes `gold.rtw_predictions`
(predicted vs actual `days_to_rtw`).

### 3. Build the Vector Search index

Import [vector_search_setup.py](vector_search_setup.py), **Run all** (cell by cell — the endpoint
takes a few minutes to come ONLINE). It creates a CDF source table from the redacted notes, an AI
Search endpoint, a delta-sync index, and runs a similarity query.

Docs: [Create AI Search endpoints and indexes](https://learn.microsoft.com/azure/databricks/ai-search/create-ai-search)

### 4. Deploy the triage app

1. **Compute ▸ Apps ▸ Create app** (or **New ▸ App**), choose a **Streamlit** custom app.
2. Add a **SQL warehouse** resource with the key `sql-warehouse` (this injects `DATABRICKS_WAREHOUSE_ID`).
3. Upload `app/` (`app.py`, `app.yaml`, `requirements.txt`) and **Deploy**.
4. Grant the app's **service principal** `SELECT` on `state_fund_poc.gold.fraud_scores` (+ `USE` on
   the catalog/schema).

The app renders the ranked triage queue with tier filters and a per-claim detail panel.

Docs: [Databricks Apps](https://learn.microsoft.com/azure/databricks/dev-tools/databricks-apps/) ·
[App runtime (app.yaml)](https://learn.microsoft.com/azure/databricks/dev-tools/databricks-apps/app-runtime)

### 5. Orchestrate end-to-end

Open [workflow/end_to_end_job.json](workflow/end_to_end_job.json), replace the `<...>` placeholders
(pipeline IDs + notebook paths), and import it (**Jobs & Pipelines ▸ Create ▸ Job**, or the Jobs
API). It chains **ingest → Bronze → Silver → Gold → score (fraud + RTW) → data quality** on
Serverless.

Docs: [Lakeflow Jobs](https://learn.microsoft.com/azure/databricks/jobs/) ·
[Pipeline task](https://learn.microsoft.com/azure/databricks/jobs/pipeline-task)

### 6. Verify governance

Import and run the three [governance/](governance/) notebooks:

- **`row_filter_demo.sql`** — see the masks/row filter on `silver.claims` (depends on your
  `pii_authorized` membership).
- **`audit_system_tables.sql`** — who accessed the POC tables + table lineage (needs `system.access`
  enabled).
- **`time_travel_recovery.sql`** — Delta history, time travel, and `RESTORE` on `gold.fraud_scores`.

Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) ·
[System tables](https://learn.microsoft.com/azure/databricks/admin/system-tables/) ·
[Delta history](https://learn.microsoft.com/azure/databricks/delta/history)

---

## Design notes

- **`@champion` indirection.** Scoring loads `models:/…@champion`, so re-registering a better model in
  Session 4 changes what serves — no code change here.
- **App reads Gold only.** The Streamlit app queries `gold.fraud_scores` via a SQL warehouse under its
  own service principal — never raw or PII tables.
- **Vector Search on redacted text.** The index embeds `note_text_redacted` (PII removed in Session
  2), so similar-claim lookup never exposes identifiers.
- **Fraud = triage acceleration.** The queue ranks claims for SIU review; it does not auto-decide
  fraud.

## Next

This completes the POC build. See the [Deployment Guide](../DEPLOYMENT_GUIDE.md) for the full
end-to-end walkthrough.
