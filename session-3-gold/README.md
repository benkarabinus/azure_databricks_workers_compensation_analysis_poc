# Session 3 — Gold: Features, Lineage & Self-Service BI

**Goal:** Feature-engineer the governed `silver.*` entities into ML-ready Gold tables and a BI
aggregate, surface data-quality metrics, and stand up self-service analytics (Genie + an AI/BI
dashboard).

**Output:** `gold.rtw_features`, `gold.fraud_features`, `gold.rtw_outcomes_summary`, a
`gold.data_quality` view, a Genie Space, and an AI/BI dashboard.

This session is a **UI walkthrough**: one Lakeflow SQL pipeline, one interactive SQL notebook, and
two UI artifacts (Genie + dashboard). Every step links to the official Microsoft Learn docs.

## Files in this folder

| File | What it is | How you use it |
| --- | --- | --- |
| [gold_pipeline.sql](gold_pipeline.sql) | Lakeflow SDP pipeline source (SQL) — the three Gold tables | Import as a SQL file, add as pipeline source code |
| [data_quality_view.sql](data_quality_view.sql) | Interactive SQL notebook — `gold.data_quality` over the Silver event log | Import as a notebook, run after the Silver pipeline |
| [genie_space.md](genie_space.md) | Genie Space configuration + sample questions | Reproduce in the Genie UI |
| [dashboard/rtw_fraud.lvdash.json](dashboard/rtw_fraud.lvdash.json) | Starter AI/BI dashboard | Import via the Dashboards UI, then refine |

## Prerequisites

- **Session 2 complete** — the six `silver.*` tables exist and are populated.
- **The Gold pipeline owner is in `pii_authorized`.** `silver.claims` has a region row filter that
  evaluates as the invoker; an unauthorized ETL identity would drop `Southern CA` claims from every
  Gold table. ([Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/))
- **UC privileges** to create materialized views in `gold` and a view there.
- **A Serverless SQL Warehouse** for Genie and the dashboard.

## The Gold tables

| Table | Grain | Purpose |
| --- | --- | --- |
| `gold.rtw_features` | one row per **closed** claim | RTW regression training set (label `days_to_rtw`) |
| `gold.fraud_features` | one row per **labeled** claim | Fraud classification training set (label `is_fraud`) |
| `gold.rtw_outcomes_summary` | injury_type × region | RTW KPIs for BI / Genie |
| `gold.data_quality` (view) | one row per Expectation | Silver Expectation pass rates from the event log |

---

## Steps

### 1. Create and run the Gold pipeline

Each Gold table is a **materialized view** that recomputes from the Silver tables. `rtw_features`
keeps closed claims only (label present); `fraud_features` is the labeled SIU subset (inner join to
`bronze.raw_siu_labels`); `rtw_outcomes_summary` aggregates `rtw_features`.

1. **Workspace ▸ ⋮ ▸ Import** [gold_pipeline.sql](gold_pipeline.sql) (imports as a workspace SQL
   file).
2. **Jobs & Pipelines ▸ Create ▸ ETL pipeline**; under **Source code** select `gold_pipeline.sql`.
3. Set **Default catalog** = `state_fund_poc` and **Default schema** = `gold`.
4. Leave compute **Serverless**; confirm the owner/run-as is in `pii_authorized`.
5. Click **Start**.

`gold` now shows `rtw_features`, `fraud_features`, and `rtw_outcomes_summary`.

Docs: [Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Window functions](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-window-functions)

### 2. Create the data-quality view

Import [data_quality_view.sql](data_quality_view.sql) as a **SQL notebook**, attach Serverless, and
**Run all** — it creates `gold.data_quality` from the **Silver** pipeline's event log (Expectation
pass/fail counts and pass rates). Run it as the Silver pipeline owner (event log access is
run-as-scoped).

Docs: [Pipeline event log](https://learn.microsoft.com/azure/databricks/ldp/monitor-event-logs) ·
[Manage data quality with expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations)

### 3. Walk the lineage

Open **Catalog ▸ `state_fund_poc` ▸ `gold` ▸ `rtw_features` ▸ Lineage** (or the pipeline graph) to
trace each Gold table back through Silver to Bronze and the source files — the same `claim_id` flows
end to end.

Docs: [Capture and view data lineage with Unity Catalog](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/data-lineage)

### 4. Configure the Genie Space

Follow [genie_space.md](genie_space.md): create the space on a Serverless SQL Warehouse, add the
three Gold tables, paste the instructions, and seed the sample questions. Test that
"which injury types have the longest average RTW by region?" returns sensible SQL.

Docs: [What is an AI/BI Genie space?](https://learn.microsoft.com/azure/databricks/genie/) ·
[Set up a Genie space](https://learn.microsoft.com/azure/databricks/genie/set-up)

### 5. Import the AI/BI dashboard

From the **Dashboards** listing, **▾ ▸ Import dashboard from file** and choose
[dashboard/rtw_fraud.lvdash.json](dashboard/rtw_fraud.lvdash.json). This is a **starter** (datasets +
a few widgets); open it, verify the visuals render against your Gold tables, and refine with
AI-assisted authoring. Publish to the `analysts` group when ready.

Docs: [Import a dashboard file](https://learn.microsoft.com/azure/databricks/dashboards/automate/import-export) ·
[AI/BI dashboards](https://learn.microsoft.com/azure/databricks/dashboards/)

---

## Design notes

- **Why materialized views?** Gold recomputes deterministically from Silver — no manual scheduling,
  and lineage is captured automatically.
- **`rtw_features` is closed-claims-only** so the `days_to_rtw` label is always present for training.
  Session 5 scores open claims by reusing this feature logic.
- **`fraud_features` is the labeled subset** (inner join to the SIU labels) because `is_fraud` exists
  only for investigated claims; the model still scores all claims in Session 5.
- **Derived in Gold:** `age_band` (from `dob` at injury), `tenure_years` (`injury_date − hire_date`),
  `prior_claims_count` (window over the worker's earlier claims), `billing_vs_claim_ratio`,
  `provider_claim_count_30d` (provider-velocity signal).
- **Fraud = triage acceleration.** `is_fraud` is a confirmed SIU label, not a model score; the
  features rank claims for investigator review, never auto-decide fraud.

## Next

Continue to **Session 4 — AutoML & MLflow**. See the [Deployment Guide](../DEPLOYMENT_GUIDE.md).
