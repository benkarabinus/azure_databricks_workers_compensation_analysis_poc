---
title: Session 3 — Gold
layout: default
nav_order: 6
---

# Session 3 — Gold: Features, Lineage & Self-Service BI

**Goal:** Feature-engineer the governed `silver.*` entities into ML-ready Gold tables and a BI
aggregate, surface data-quality metrics, and stand up self-service analytics (Genie + AI/BI
dashboard).

**Output:** `gold.rtw_features`, `gold.fraud_features`, `gold.rtw_outcomes_summary`, a
`gold.data_quality` view, a Genie Space, and an AI/BI dashboard.

All assets live under `session-3-gold/`. You run one Lakeflow SQL pipeline, one interactive SQL
notebook, and two UI artifacts (Genie + dashboard).

## Source files

| File | What it is | How you use it |
| --- | --- | --- |
| `gold_pipeline.sql` | Lakeflow SDP source (SQL) — the three Gold tables | Import as a SQL file, add as pipeline source code |
| `data_quality_view.sql` | Interactive SQL — `gold.data_quality` from the Silver event log | Import as a notebook, run after the Silver pipeline |
| `genie_space.md` | Genie Space configuration + sample questions | Reproduce in the Genie UI |
| `dashboard/rtw_fraud.lvdash.json` | Starter AI/BI dashboard | Import via the Dashboards UI, then refine |

## The Gold tables

| Table | Grain | Purpose |
| --- | --- | --- |
| `gold.rtw_features` | one row per **closed** claim | RTW regression training set (`days_to_rtw`) |
| `gold.fraud_features` | one row per **labeled** claim | Fraud classification training set (`is_fraud`) |
| `gold.rtw_outcomes_summary` | injury_type × region | RTW KPIs for BI / Genie |
| `gold.data_quality` (view) | one row per Expectation | Silver Expectation pass rates |

## Prerequisites

- **Session 2 complete** — the six `silver.*` tables exist.
- **The Gold pipeline owner is in `pii_authorized`** (the `silver.claims` row filter evaluates as the
  invoker). ([Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/))
- **A Serverless SQL Warehouse** for Genie and the dashboard.

---

## Steps

### 1. Create and run the Gold pipeline

Import `gold_pipeline.sql` (workspace SQL file), create a **Serverless ETL pipeline** with it as
source code, **Default catalog** `state_fund_poc`, **Default schema** `gold`, confirm the owner is in
`pii_authorized`, and **Start**. Each table is a materialized view: `rtw_features` (closed claims +
`days_to_rtw`), `fraud_features` (labeled subset + `is_fraud`), `rtw_outcomes_summary` (aggregate).

Docs: [Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Window functions](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-window-functions)

### 2. Create the data-quality view

Import `data_quality_view.sql` as a **SQL notebook** and **Run all** — creates `gold.data_quality`
from the Silver pipeline's event log (Expectation pass/fail counts and pass rates). Run as the Silver
pipeline owner (event-log access is run-as-scoped).

Docs: [Pipeline event log](https://learn.microsoft.com/azure/databricks/ldp/monitor-event-logs) ·
[Expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations)

### 3. Walk the lineage

**Catalog ▸ `gold` ▸ `rtw_features` ▸ Lineage** traces each Gold table back through Silver to Bronze
and the source files — the same `claim_id` end to end.

Docs: [Data lineage with Unity Catalog](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/data-lineage)

### 4. Configure the Genie Space

Follow `genie_space.md`: create the space, add the three Gold tables, paste the instructions, seed
sample questions, and test "which injury types have the longest average RTW by region?".

Docs: [AI/BI Genie](https://learn.microsoft.com/azure/databricks/genie/) ·
[Set up a Genie space](https://learn.microsoft.com/azure/databricks/genie/set-up)

### 5. Import the AI/BI dashboard

**Dashboards ▸ ▾ ▸ Import dashboard from file** ▸ `dashboard/rtw_fraud.lvdash.json`. It's a starter
(datasets + a few widgets) — verify the visuals render, refine with AI-assisted authoring, and
publish to `analysts`.

Docs: [Import a dashboard file](https://learn.microsoft.com/azure/databricks/dashboards/automate/import-export) ·
[AI/BI dashboards](https://learn.microsoft.com/azure/databricks/dashboards/)

---

## Design notes

- **Materialized views** recompute deterministically from Silver; lineage is automatic.
- **`rtw_features` is closed-claims-only** (label always present); Session 5 scores open claims with
  the same feature logic.
- **`fraud_features` is the labeled subset** (inner join to SIU labels); the model scores all claims
  later.
- **Derived in Gold:** `age_band`, `tenure_years`, `prior_claims_count`, `billing_vs_claim_ratio`,
  `provider_claim_count_30d`.
- **Fraud = triage acceleration** — `is_fraud` is a confirmed label, not a model score.

## Next

Continue to **Session 4 — AutoML & MLflow**.
