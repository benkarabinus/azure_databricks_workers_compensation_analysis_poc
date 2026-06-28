---
title: Home
layout: home
nav_order: 1
---

# State Fund Azure Databricks Serverless POC: Example ETL and Serving Workflow

A hands-on tutorial that builds an end-to-end lakehouse medallion architecture (Bronze → Silver → Gold) on **Azure Databricks Serverless.** This walkthrough is designed for California State Compensation Insurance Fund and is inteneded to familiarize users with the Azure Databricks platform by delivering two machine-learning use cases on synthetic workers' compensation data:

- **Return-to-Work (RTW) duration prediction** — regression on `days_to_rtw`.
- **Claims fraud investigation triage** — classification producing a `fraud_risk_score` that ranks open claims for SIU review.

> All data is **synthetic**. All compute is **serverless**. Fraud is framed as **investigation triage acceleration**, not fully automated fraud detection.

![Medallion architecture — Sources → Bronze → Silver → Gold → ML / Serving / BI, governed by Unity Catalog](diagrams/medallion-architecture.svg)

## How this tutorial works

The build is split into ordered **sessions**, each a self-contained stage. Work them in order — each depends on the catalog, schemas, and tables created earlier.

| Session | Focus | Key outputs |
| --- | --- | --- |
| **0 — Setup** | Terraform provisions a serverless workspace + dedicated ADLS Gen2 External Location (Unity Catalog auto-enabled) | Working serverless workspace |
| **1 — Bronze** | Catalog/schemas, Auto Loader DLT (CSV/JSON) + Excel ingest | `bronze.raw_*` tables |
| **2 — Silver** | Cleaning, DLT Expectations, PII masking, AI Functions on notes | governed `silver.*` |
| **3 — Gold** | Feature tables, BI aggregates, lineage, Genie, AI/BI dashboard | ML-ready `gold.*` + BI |
| **4 — ML** | Serverless scikit-learn training (RTW + fraud), MLflow, register to Unity Catalog | `ml.rtw_model`, `ml.fraud_model` |
| **5 — Serving** | Batch scoring, Streamlit triage app, Vector Search, Workflow, governance | live app + automated pipeline |

All session pages are published here; the full step-by-step walkthrough also lives in `DEPLOYMENT_GUIDE.md` in the root of the GitHub repository that backs this pages site.

## Understand the sample data

Before you build, review the [sample data dictionary](data-dictionary.html) — it walks the synthetic dataset from raw Bronze through to ML-ready Gold, with an entity-relationship diagram and an explanation of each table.

## Getting started

1. Open the **view on GitHub** URL in the top right corner of this page in a new tab.
2. Download the repository source files as Zip and then unzip the package to a location on your local machine.
3. Start with **Session 0** to stand up the workspace and continue through **Session 5** to complete the POC tutorial.
4. Use the examples provided in this POC as a baseline for building somehting new and continuing to familiarize yourself with Azure Databricks.

Learn more about the platform in [Azure Databricks documentation](https://learn.microsoft.com/azure/databricks/).
