"""Synthetic source-data generator for the State Fund Lane 1 POC.

Generates the six source files consumed by the Bronze layer:

    claims_core.csv         claims hub (simulates a claims DB)
    hr_records.csv          employee / employment records (simulates SQL Server backed HRIS)
    medical_treatments.json nested treatment events per claim (JSON Lines)
    provider_billing.json   nested billing lines per claim (JSON Lines, simulates EDI 837)
    adjuster_notes.xlsx     free-text adjuster notes with embedded fake PII
    siu_labels.csv          confirmed SIU fraud labels for a labeled subset

All data is **fully synthetic** (Faker-generated) and the RNG is seeded for
reproducibility. A small share of rows is deliberately "dirtied" (mixed date
formats, casing/whitespace, placeholder nulls, invalid SSNs, duplicate
``claim_id``, orphan foreign keys, embedded PII) so the Silver cleaning and
governance demos have something to do.

This script only writes the files to a local folder. Uploading them to the
ADLS Gen2 External Location (which triggers the Bronze pipelines in Databricks)
is a manual step performed by participants during the workshop sessions.

Run locally::

    pip install pandas numpy faker openpyxl
    python data/generate_synthetic_data.py --num-claims 5000 --seed 42 --out data

The same claim IDs flow through every downstream layer, so do not change the ID
scheme without updating the pipelines.
"""

from __future__ import annotations

import argparse
import json
import random
from datetime import date, datetime, timedelta
from pathlib import Path

try:
    import numpy as np
    import pandas as pd
    from faker import Faker
except ImportError as exc:  # pragma: no cover - dependency guard
    raise SystemExit(
        "Missing dependencies. Install them with:\n"
        "    pip install pandas numpy faker openpyxl"
    ) from exc


# --------------------------------------------------------------------------- #
# Reference value pools
# --------------------------------------------------------------------------- #

REGIONS = ["Bay Area", "Southern CA", "Northern CA", "Central Valley", "Sacramento", "Inland Empire"]

# injury_type -> plausible body parts
INJURY_BODY_PARTS: dict[str, list[str]] = {
    "Strain": ["Lower Back", "Neck", "Shoulder"],
    "Sprain": ["Ankle", "Wrist", "Knee"],
    "Fracture": ["Wrist", "Leg", "Arm", "Hand"],
    "Laceration": ["Hand", "Forearm", "Scalp"],
    "Contusion": ["Shoulder", "Hip", "Thigh"],
    "Burn": ["Arm", "Hand", "Face"],
}
INJURY_TYPES = list(INJURY_BODY_PARTS)

JOB_CLASSES = ["Laborer", "Driver", "Machinist", "Warehouse", "Welder", "Supervisor", "Office", "Construction"]

TREATMENT_TYPES = ["office_visit", "physical_therapy", "imaging", "specialist_consult", "follow_up"]
PROVIDER_SPECIALTIES = ["Orthopedics", "General", "Chiropractic", "Specialist", "Physical Therapy"]
BILLING_CODES = ["99213", "99214", "99215", "99205", "97110", "73610", "29826", "20680"]

ADJUSTERS = [f"ADJ-{i:02d}" for i in range(1, 16)]

# Severity multipliers feed the RTW duration model signal.
SEVERITY = {"Strain": 1.0, "Sprain": 0.8, "Laceration": 0.5, "Contusion": 0.7, "Fracture": 2.2, "Burn": 2.0}


# --------------------------------------------------------------------------- #
# Date helpers (for deliberately inconsistent formatting)
# --------------------------------------------------------------------------- #

_MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


def fmt_date(d: date, style: str = "iso") -> str:
    """Format a date in one of several styles to simulate dirty source data."""
    if style == "iso":
        return d.strftime("%Y-%m-%d")
    if style == "us":
        return d.strftime("%m/%d/%Y")
    if style == "dmon":
        return f"{d.day:02d}-{_MONTHS[d.month - 1]}-{d.year}"
    raise ValueError(style)


def messy_date(rng: random.Random, d: date) -> str:
    """Return a date string with an inconsistent (but parseable) format."""
    style = rng.choices(["iso", "us", "dmon"], weights=[0.7, 0.2, 0.1])[0]
    return fmt_date(d, style)


def _us_no_pad(d: date) -> str:
    """US-style date without zero padding (e.g. ``1/20/2025``), portable across OSes."""
    return f"{d.month}/{d.day}/{d.year}"


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #


def generate(num_claims: int, seed: int) -> dict[str, object]:
    """Generate all in-memory records. Returns a dict of named datasets."""
    rng = random.Random(seed)
    np_rng = np.random.default_rng(seed)
    fake = Faker("en_US")
    Faker.seed(seed)

    # ---- Employees (fewer workers than claims -> many claims per worker) ----
    num_workers = max(1, int(num_claims * 0.8))
    employers = [f"EMP-{i:03d}" for i in range(100, 100 + 40)]
    employees = []
    for i in range(1, num_workers + 1):
        emp_id = f"EMP-W-{1000 + i}"
        hire = date(2025, 1, 1) - timedelta(days=rng.randint(180, 365 * 25))
        wage = int(np_rng.normal(62000, 18000))
        wage = max(28000, min(160000, wage))
        employees.append(
            {
                "employee_id": emp_id,
                "full_name": fake.name(),
                "job_class": rng.choice(JOB_CLASSES),
                "hire_date": hire,
                "annual_wage": wage,
                "employer_id": rng.choice(employers),
            }
        )
    worker_ids = [e["employee_id"] for e in employees]

    # ---- Claims --------------------------------------------------------------
    claims = []
    treatments = []
    billing = []
    notes = []
    labels = []

    # A subset of claims is "investigated" (labeled) for fraud training.
    label_fraction = 0.45
    fraud_rate_within_labeled = 0.10  # ~8-12% positive class

    provider_pool = [f"{2000 + i}" for i in range(200)]  # provider NPIs

    base_injury = date(2024, 1, 1)
    horizon_days = 540

    for n in range(1, num_claims + 1):
        claim_id = f"CLM-{n:05d}"
        worker = rng.choice(worker_ids)
        emp = next(e for e in employees if e["employee_id"] == worker)

        injury_type = rng.choice(INJURY_TYPES)
        body_part = rng.choice(INJURY_BODY_PARTS[injury_type])
        injury_dt = base_injury + timedelta(days=rng.randint(0, horizon_days))

        # Decide fraud + label membership first (drives correlated signals).
        is_labeled = rng.random() < label_fraction
        is_fraud = is_labeled and (rng.random() < fraud_rate_within_labeled)

        # Reporting lag: fraud-positive claims report later.
        report_lag = rng.randint(8, 30) if is_fraud else rng.randint(0, 5)
        reported_dt = injury_dt + timedelta(days=report_lag)

        # Closure / RTW: ~70% of claims are closed (have an RTW date).
        closed = rng.random() < 0.70
        severity = SEVERITY[injury_type]
        age_factor = rng.uniform(0.8, 1.4)
        surgery = injury_type in ("Fracture", "Burn") and rng.random() < 0.6
        base_days = 14 + severity * 30 * age_factor + (40 if surgery else 0)
        days_to_rtw = int(max(5, np_rng.normal(base_days, base_days * 0.2)))
        rtw_dt = injury_dt + timedelta(days=days_to_rtw) if closed else None

        claim_amount = round(float(np_rng.normal(8000 * severity, 2500 * severity)), 2)
        claim_amount = max(800.0, claim_amount)

        claims.append(
            {
                "claim_id": claim_id,
                "claimant_name": emp["full_name"],
                "ssn": fake.ssn(),
                "dob": fake.date_of_birth(minimum_age=18, maximum_age=64),
                "injury_date": injury_dt,
                "reported_date": reported_dt,
                "injury_type": injury_type,
                "body_part": body_part,
                "claim_status": "CLOSED" if closed else "OPEN",
                "adjuster_id": rng.choice(ADJUSTERS),
                "region": rng.choice(REGIONS),
                "claim_amount": claim_amount,
                "employee_id": worker,
                # internal-only fields (not written raw; used for label realism)
                "_rtw_date": rtw_dt,
                "_surgery": surgery,
                "_is_labeled": is_labeled,
                "_is_fraud": is_fraud,
            }
        )

        # ---- Treatments (nested events) -------------------------------------
        n_events = rng.randint(2, 14 if surgery else 8)
        primary_specialty = rng.choice(PROVIDER_SPECIALTIES)
        events = []
        first_treat = injury_dt + timedelta(days=rng.randint(1, 7))
        for ev in range(n_events):
            ev_date = first_treat + timedelta(days=ev * rng.randint(3, 14))
            ttype = "office_visit" if ev == 0 else rng.choice(TREATMENT_TYPES)
            if surgery and ev == 1:
                ttype = "surgery"
            events.append(
                {
                    "event_date": ev_date.strftime("%Y-%m-%d"),
                    "treatment_type": ttype,
                    "provider_npi": rng.choice(provider_pool),
                    "provider_specialty": primary_specialty,
                }
            )
        # Closed claims carry a return_to_work event (source of rtw_date).
        if rtw_dt is not None:
            events.append(
                {
                    "event_date": rtw_dt.strftime("%Y-%m-%d"),
                    "treatment_type": "return_to_work",
                    "provider_npi": rng.choice(provider_pool),
                    "provider_specialty": primary_specialty,
                }
            )
        treatments.append({"claim_id": claim_id, "events": events})

        # ---- Provider billing (nested lines) --------------------------------
        if is_fraud:
            n_providers = rng.randint(5, 8)
            ratio = rng.uniform(3.0, 4.2)
        else:
            n_providers = rng.randint(1, 2)
            ratio = rng.uniform(0.9, 1.1)
        billing_total_target = claim_amount * ratio
        n_lines = max(n_providers, rng.randint(n_providers, n_providers + 4))
        line_providers = rng.sample(provider_pool, n_providers)
        lines = []
        remaining = billing_total_target
        for li in range(n_lines):
            amt = round(remaining / (n_lines - li), 2) if li < n_lines - 1 else round(remaining, 2)
            amt = max(50.0, amt * rng.uniform(0.7, 1.3))
            remaining = max(0.0, remaining - amt)
            svc = first_treat + timedelta(days=rng.randint(0, 60))
            lines.append(
                {
                    "billing_code": rng.choice(BILLING_CODES),
                    "provider_npi": rng.choice(line_providers),
                    "billed_amount": round(amt, 2),
                    "service_date": svc.strftime("%Y-%m-%d"),
                }
            )
        billing.append({"claim_id": claim_id, "billing_lines": lines})

        # ---- Adjuster notes (subset of claims) ------------------------------
        if rng.random() < 0.55:
            attorney = is_fraud and rng.random() < 0.7
            if is_fraud:
                note = (
                    f"Multiple providers billing same period; claimant {emp['full_name']} "
                    f"uncooperative (cell {fake.phone_number()}); treatment far from home."
                )
                if attorney:
                    note += " Attorney involved early (atty J. Marlin)."
                follow_up = "yes"
            else:
                note = rng.choice(
                    [
                        f"Routine {injury_type.lower()} to {body_part.lower()}; expected standard recovery.",
                        f"Claimant {emp['full_name']} (DOB {fake.date_of_birth(minimum_age=18, maximum_age=64):%m/%d/%Y}) "
                        f"following treatment plan; ph {fake.phone_number()}.",
                        "Released to modified duty; progressing as expected.",
                    ]
                )
                follow_up = rng.choice(["no", "yes"])
            notes.append(
                {
                    "claim_id": claim_id,
                    "adjuster_id": rng.choice(ADJUSTERS),
                    "note_date": _us_no_pad(reported_dt + timedelta(days=rng.randint(1, 20))),
                    "note_text": note,
                    "follow_up_required": follow_up,
                }
            )

        # ---- SIU labels (labeled subset only) -------------------------------
        if is_labeled:
            labels.append({"claim_id": claim_id, "is_fraud": int(is_fraud)})

    return {
        "employees": employees,
        "claims": claims,
        "treatments": treatments,
        "billing": billing,
        "notes": notes,
        "labels": labels,
        "rng": rng,
    }


# --------------------------------------------------------------------------- #
# Dirty-data injection + serialization
# --------------------------------------------------------------------------- #


def _dirty_claims_frame(claims: list[dict], rng: random.Random) -> pd.DataFrame:
    """Build the claims_core DataFrame with deliberate dirty patterns (~2-5%)."""
    rows = []
    for c in claims:
        name = c["claimant_name"]
        injury_s = messy_date(rng, c["injury_date"])
        reported_s = messy_date(rng, c["reported_date"])
        dob_s = messy_date(rng, c["dob"])
        ssn = c["ssn"]
        injury_type = c["injury_type"]
        region = c["region"]
        amount: object = c["claim_amount"]
        emp_id = c["employee_id"]

        r = rng.random()
        if r < 0.03:  # casing / whitespace noise
            injury_type = rng.choice([injury_type.upper(), injury_type.lower(), injury_type + "  "])
            region = region.lower()
            name = f"{name.split()[-1]}, {name.split()[0]}"  # "Last, First"
        elif r < 0.05:  # invalid SSN
            ssn = rng.choice(["555-0100", "000000000", "12-345-678"])
        elif r < 0.07:  # placeholder nulls
            region = rng.choice(["N/A", "unknown", ""])
        elif r < 0.085:  # un-cast / negative amount
            amount = rng.choice([str(int(c["claim_amount"])), -abs(c["claim_amount"])])
        elif r < 0.10:  # orphan FK (employee not in HR)
            emp_id = "EMP-W-9999"

        rows.append(
            {
                "claim_id": c["claim_id"],
                "claimant_name": name,
                "ssn": ssn,
                "dob": dob_s,
                "injury_date": injury_s,
                "reported_date": reported_s,
                "injury_type": injury_type,
                "body_part": c["body_part"],
                "claim_status": c["claim_status"],
                "adjuster_id": c["adjuster_id"],
                "region": region,
                "claim_amount": amount,
                "employee_id": emp_id,
            }
        )

    df = pd.DataFrame(rows)

    # ~2% duplicate claim_id rows (later-ingested duplicates).
    dupes = df.sample(frac=0.02, random_state=rng.randint(0, 10_000))
    # A single poison row exercising multiple violations at once.
    poison = pd.DataFrame(
        [
            {
                "claim_id": "CLM-00099",
                "claimant_name": "Test User",
                "ssn": "000000000",
                "dob": "01/01/1900",
                "injury_date": "12/31/2099",
                "reported_date": "",
                "injury_type": "unknown",
                "body_part": "N/A",
                "claim_status": "OPEN",
                "adjuster_id": "ADJ-99",
                "region": "-1",
                "claim_amount": -500.0,
                "employee_id": "EMP-W-9999",
            }
        ]
    )
    return pd.concat([df, dupes, poison], ignore_index=True)


def _dirty_hr_frame(employees: list[dict], rng: random.Random) -> pd.DataFrame:
    rows = []
    for e in employees:
        job = e["job_class"]
        hire_s = messy_date(rng, e["hire_date"])
        wage: object = e["annual_wage"]
        r = rng.random()
        if r < 0.03:
            job = rng.choice([job.lower(), job + " "])
        elif r < 0.05:
            wage = str(e["annual_wage"])  # string instead of int
        rows.append(
            {
                "employee_id": e["employee_id"],
                "full_name": e["full_name"],
                "job_class": job,
                "hire_date": hire_s,
                "annual_wage": wage,
                "employer_id": e["employer_id"],
            }
        )
    return pd.DataFrame(rows)


def write_jsonl(path: Path, records: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate synthetic source data for the POC.")
    parser.add_argument("--num-claims", type=int, default=5000, help="Number of claims to generate (default 5000).")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility (default 42).")
    parser.add_argument("--out", type=str, default="data", help="Output directory (default ./data).")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"Generating {args.num_claims} claims (seed={args.seed}) -> {out.resolve()}")
    data = generate(args.num_claims, args.seed)
    rng: random.Random = data["rng"]

    # claims_core.csv
    claims_df = _dirty_claims_frame(data["claims"], rng)
    claims_df.to_csv(out / "claims_core.csv", index=False)
    print(f"  claims_core.csv          {len(claims_df):>7} rows")

    # hr_records.csv
    hr_df = _dirty_hr_frame(data["employees"], rng)
    hr_df.to_csv(out / "hr_records.csv", index=False)
    print(f"  hr_records.csv           {len(hr_df):>7} rows")

    # medical_treatments.json (JSON Lines, nested events[])
    write_jsonl(out / "medical_treatments.json", data["treatments"])
    print(f"  medical_treatments.json  {len(data['treatments']):>7} claims")

    # provider_billing.json (JSON Lines, nested billing_lines[])
    write_jsonl(out / "provider_billing.json", data["billing"])
    print(f"  provider_billing.json    {len(data['billing']):>7} claims")

    # adjuster_notes.xlsx
    notes_df = pd.DataFrame(data["notes"])
    notes_df.to_excel(out / "adjuster_notes.xlsx", index=False, engine="openpyxl")
    print(f"  adjuster_notes.xlsx      {len(notes_df):>7} rows")

    # siu_labels.csv
    labels_df = pd.DataFrame(data["labels"])
    labels_df.to_csv(out / "siu_labels.csv", index=False)
    pos = int(labels_df["is_fraud"].sum()) if len(labels_df) else 0
    print(f"  siu_labels.csv           {len(labels_df):>7} rows ({pos} fraud)")

    print("Done.")


if __name__ == "__main__":
    main()
