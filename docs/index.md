---
title: Home
layout: home
nav_order: 1
---

# State Fund Lane 1 POC

A hands-on tutorial that builds an end-to-end **medallion (Bronze → Silver → Gold) lakehouse** on **Azure Databricks Serverless** for the California State Fund, delivering two machine-learning use cases on synthetic workers'-compensation data:

- **Return-to-Work (RTW) duration prediction** — regression on `days_to_rtw`.
- **Claims fraud investigation triage** — classification producing a `fraud_risk_score` that ranks open claims for SIU review.

> All data is **synthetic**. All compute is **serverless**. Fraud is framed as **investigation triage acceleration**, never automated fraud detection.

## How this tutorial works

The build is split into ordered **sessions**, each a self-contained stage. Work them in order — each depends on the catalog, schemas, and tables created earlier.

| Session | Focus | Key outputs |
| --- | --- | --- |
| **0 — Setup** | Workspace, Unity Catalog metastore, serverless, dedicated ADLS Gen2 External Location, access | Working serverless workspace |
| **1 — Bronze** | Catalog/schemas; Auto Loader DLT (CSV/JSON) + Excel ingest | `bronze.raw_*` tables |
| **2 — Silver** | Cleaning, DLT Expectations, PII masking, AI Functions on notes | governed `silver.*` |
| **3 — Gold** | Feature tables, BI aggregates, lineage, Genie, AI/BI dashboard | ML-ready `gold.*` + BI |
| **4 — ML** | AutoML (RTW + fraud), MLflow, register to Unity Catalog | `ml.rtw_model`, `ml.fraud_model` |
| **5 — Serving** | Batch scoring, Streamlit triage app, Vector Search, Workflow, governance | live app + automated pipeline |

Session pages are published here as each session is built. Until then, the full walkthrough lives in `DEPLOYMENT_GUIDE.md` in the repository root.

## Understand the sample data

Before you build, review the [sample data dictionary](data-dictionary.html) — it walks the synthetic dataset from raw Bronze through to ML-ready Gold, with an entity-relationship diagram and an explanation of each table.

## Getting started

1. Generate the synthetic source data locally (see the repository `README.md`).
2. Follow the deployment guide from **Session 0** to stand up the workspace.
3. Upload the generated files to the ADLS Gen2 External Location to trigger the Bronze pipelines, and continue through Session 5.

Learn more about the platform in the [Azure Databricks documentation](https://learn.microsoft.com/azure/databricks/).
