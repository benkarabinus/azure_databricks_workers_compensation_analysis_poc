# Build Log — State Fund Lane 1 POC

> **Purpose:** Working progress log so any new session (or a compacted context window) can resume the build without re-deriving decisions. This is a **working doc**, not the published `CHANGELOG.md`. Update it at the end of each meaningful unit of work: what changed, why, and what's next.

## Current status

- **Phase:** Customization complete; **scaffolding in progress (step 1 done).**
- **Local env:** project **`.venv`** (Python 3.12) holds data-gen/dev deps from `requirements.txt`. Do NOT install into system Python. Activate with `.venv\Scripts\python`.
- **Primary instructions:** `.github/copilot-instructions.md` is the source of truth for structure, sessions, architecture, and conventions.
- **Reference (do not ship):** `state-fund-lane1-poc-implementation-plan.md` — full design (ERD, column lineage, sample data, ML plan). Keep for scaffolding context.

## Locked decisions

- **Use case:** California State Fund Lane 1 POC — RTW duration prediction (regression) + claims fraud investigation triage (classification). Frame fraud as *triage acceleration*, never "automated fraud detection."
- **Platform:** Azure Databricks **Serverless** only (no classic clusters). Medallion Bronze → Silver → Gold.
- **Unity Catalog:** single catalog `state_fund_poc`; schemas `bronze`, `silver`, `gold`, `config`, `security`, `ml`. Bronze tables prefixed `raw_`.
- **Storage:** dedicated ADLS Gen2 registered as a UC External Location (separate from metastore root).
- **Repo style:** CalmVault-like tutorial — `README.md` (landing), `DEPLOYMENT_GUIDE.md` (full walkthrough), `docs/` Jekyll Pages site (just-the-docs), session-per-folder.
- **Databricks App:** **Streamlit** (reads `gold.fraud_scores` only).
- **Synthetic data:** Python pandas/Faker, seeded; inject ~2–5% dirty patterns.
- **Docs rule:** every session step must cite verified Microsoft Learn / Databricks docs (no guessed URLs); keep `session-N/README.md`, `docs/session-N.md`, and `DEPLOYMENT_GUIDE.md` in sync.
- **Diagrams:** `.drawio` sources under `docs/diagrams/` + exported `.svg`/`.png`, Azure/Databricks icons; reference exported image in Markdown.

## Customization layer (DONE)

- `.github/copilot-instructions.md` — promoted primary instructions.
- `.github/instructions/pyspark.instructions.md` — `**/*.py`.
- `.github/instructions/sql.instructions.md` — `**/*.sql`.
- `.github/instructions/diagrams.instructions.md` — `**/*.drawio, docs/diagrams/**`.

## Planned build order (TODO)

1. ✅ `common/config.py` + `data/generate_synthetic_data.py` (+ `requirements.txt`, `.gitignore`, `.venv`). Smoke-tested at 100 claims.
2. `README.md` + `DEPLOYMENT_GUIDE.md` skeletons; `docs/` Jekyll site (`_config.yml`, `Gemfile`, `index.md`).
3. Session 0 — setup SQL + README.
4. Session 1 — Bronze (catalog/schemas, Auto Loader DLT, Excel ingest).
5. Session 2 — Silver (DLT Expectations, masking, AI functions).
6. Session 3 — Gold (feature tables, quality view, Genie, dashboard).
7. Session 4 — ML (AutoML RTW + fraud, register models).
8. Session 5 — Serving (batch scoring, Streamlit app, Vector Search, Workflow, governance).
9. Architecture diagram(s) under `docs/diagrams/`.

## Log

- **2026-06-19** — Generated the full synthetic dataset into `data/` at 5,000 claims (seed 42): claims_core.csv (5,101 rows w/ dupes+poison), hr_records.csv (4,000), medical_treatments.json (5,000, ~4 MB), provider_billing.json (5,000, ~2.2 MB), adjuster_notes.xlsx (2,760), siu_labels.csv (2,260 labeled, 232 fraud ≈ 10.3%). ~7 MB total.
- **2026-06-19** — Step 1: created `common/config.py` (catalog/schema/table/path helpers), `common/__init__.py`, `data/generate_synthetic_data.py` (seeded pandas/Faker generator for all six sources w/ ~2-5% dirty patterns, nested JSONL, return_to_work events, SIU labels). Added `requirements.txt` + `.gitignore`. Created project `.venv` (Python 3.12); reverted accidental system-Python (arm64) installs. Smoke-tested generator at 100 claims — all six files produced.
- **2026-06-19** — Authored & promoted `.github/copilot-instructions.md`; aligned pyspark/sql instruction files; added diagrams instruction file; created this build log + repo memory. Scaffolding pending.
