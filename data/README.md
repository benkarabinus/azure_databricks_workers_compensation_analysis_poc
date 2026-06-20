# Sample Data

Fully **synthetic** workers'-compensation source data for the State Fund Lane 1 POC (no real claimant data). The same `claim_id` threads through every medallion layer, Bronze → Silver → Gold.

## Files

| File | Bronze table | Represents | Grain |
| --- | --- | --- | --- |
| `claims_core.csv` | `bronze.raw_claims` | Core claim record (the hub) — simulates a claims DB | one row per claim |
| `hr_records.csv` | `bronze.raw_hr_records` | Employee tenure, job class, wage, employer — simulates an HR DB | one row per worker |
| `medical_treatments.json` | `bronze.raw_medical_treatments` | Treatment events per claim (nested `events[]`) | one row per claim |
| `provider_billing.json` | `bronze.raw_provider_billing` | Billing lines per claim (nested `billing_lines[]`, simulates EDI 837) | one row per claim |
| `adjuster_notes.xlsx` | `bronze.raw_adjuster_notes` | Free-text adjuster notes with embedded fake PII | one row per note |
| `siu_labels.csv` | `bronze.raw_siu_labels` | Confirmed SIU fraud labels (training subset) | one row per labeled claim |

A small share of rows is deliberately "dirty" (mixed date formats, casing/whitespace, invalid SSNs, duplicate `claim_id`, an orphan FK, embedded PII, and a poison row) so the Silver cleaning and governance demos have something to do.

## Regenerate / resize

The files are committed, so you only need this to regenerate or change the volume. Use the project virtual environment (see the repo `README.md`):

```powershell
# PowerShell
.\.venv\Scripts\python data/generate_synthetic_data.py --num-claims 5000 --seed 42 --out data
```

```bash
# Bash
.venv/bin/python data/generate_synthetic_data.py --num-claims 5000 --seed 42 --out data
```

## Full data dictionary + ERD

For the layer-by-layer dictionary (Bronze → Silver → Gold), an entity-relationship diagram, and an explanation of the Gold feature tables and why they end where they do, see [docs/data-dictionary.md](../docs/data-dictionary.md) — also published on the tutorial's GitHub Pages site.
