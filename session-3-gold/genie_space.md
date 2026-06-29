# Session 3 — Genie Space configuration

> Also published on the tutorial site: **Session 3 — Gold ▸ Genie Space setup** (`docs/session-3-genie.md`). Keep the two in sync.

A **Genie Space** lets business users ask natural-language questions over the Gold tables and get
answers as tables/charts, backed by generated (and reviewable) SQL. This file is the configuration
you reproduce in the workspace UI — Genie Spaces are created interactively, not from a source file.

Docs: [What is an AI/BI Genie space?](https://learn.microsoft.com/azure/databricks/genie/) ·
[Set up a Genie space](https://learn.microsoft.com/azure/databricks/genie/set-up) ·
[Curate an effective Genie space](https://learn.microsoft.com/azure/databricks/genie/best-practices)

## 1. Create the space

**Genie** (left nav) ▸ **New** ▸ name it `State Fund — RTW & Fraud Triage`, and use a **Serverless SQL
Warehouse** as the compute.

## 2. Add data (Gold only)

Add these governed Gold tables:

| Table | Grain | Use |
| --- | --- | --- |
| `state_fund_poc.gold.rtw_outcomes_summary` | injury_type × region | RTW KPIs (the main BI table) |
| `state_fund_poc.gold.rtw_features` | one row per closed claim | RTW drill-down / distributions |
| `state_fund_poc.gold.fraud_features` | one row per labeled claim | fraud signal exploration |

## 3. General instructions (context)

Paste this into the space's **Instructions** so Genie answers in domain terms and frames fraud
correctly:

```
This workspace analyzes California workers' compensation claims.
- `days_to_rtw` is the number of days from injury to return-to-work; lower is better.
- `gold.rtw_outcomes_summary` is pre-aggregated by injury_type and region. Prefer it for
  "average / by region / by injury type" questions.
- `gold.fraud_features.is_fraud` is a confirmed SIU label available only on a labeled subset; it is
  NOT a model score. Frame fraud work as "investigation triage", never "automated fraud detection".
- `billing_vs_claim_ratio` > ~2 and high `distinct_providers` / `provider_claim_count_30d` are
  fraud-investigation signals, not proof of fraud.
- Join key across tables is `claim_id`.
```

## 4. Sample questions (NLQ) to seed & test

Ask some sample questions and verify Genie returns sensible SQL/answers:

| Question | Should use | Expected shape |
| --- | --- | --- |
| Which injury types have the longest average return-to-work by region? | `rtw_outcomes_summary` | `injury_type, region, avg_days_to_rtw` sorted desc |
| What is the average days to RTW for fractures vs strains? | `rtw_outcomes_summary` | 2 rows, avg_days_to_rtw |
| Which region has the highest surgery rate? | `rtw_outcomes_summary` | region, pct_surgery |
| How many labeled claims are fraud vs not fraud? | `fraud_features` | count by `is_fraud` |
| What is the average billing-to-claim ratio for fraud vs non-fraud claims? | `fraud_features` | avg `billing_vs_claim_ratio` by `is_fraud` |
| Show the 10 labeled claims with the highest billing-to-claim ratio. | `fraud_features` | top 10 by `billing_vs_claim_ratio` |
| Do claims with an attorney mention have higher fraud rates? | `fraud_features` | fraud rate by `attorney_flag` |

## 5. Curation tips

- Mark `rtw_outcomes_summary` as the **trusted** table for RTW KPI questions so Genie prefers it.
- Add **SQL example queries** (Genie "Instructions ▸ Example queries") to anchor Genie's joins/aggregations.
- Re-test after each Gold pipeline change. Genie answers shift with the data.
- Publish the space to the `analysts` group once validated.
