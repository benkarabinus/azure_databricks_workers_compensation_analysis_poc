-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 2 — Grants & masking validation
-- MAGIC
-- MAGIC Run this **interactively** (SQL notebook on Serverless) **after** the Silver pipeline has
-- MAGIC created the `silver.*` tables. It grants analyst read access and then validates that the
-- MAGIC column masks and row filter on `silver.claims` behave correctly.
-- MAGIC
-- MAGIC ## Prerequisite — account groups (manual)
-- MAGIC Create two **account groups** in the [account console](https://accounts.azuredatabricks.net)
-- MAGIC (Identity and access ▸ Groups) before running the grants below, or the `GRANT` statements
-- MAGIC will fail on an unknown principal:
-- MAGIC
-- MAGIC | Group | Who | Sees |
-- MAGIC | --- | --- | --- |
-- MAGIC | `analysts` | BI / case-management users | masked SSN/DOB, no `Southern CA` rows |
-- MAGIC | `pii_authorized` | SIU / privileged users **and the pipeline owner** | full values, all rows |
-- MAGIC
-- MAGIC > **Important:** add the **pipeline owner** (the identity that runs the Silver pipeline) to
-- MAGIC > `pii_authorized`. The row filter on `silver.claims` evaluates `is_account_group_member`
-- MAGIC > as the *invoker*, so if the ETL identity is not authorized, every downstream table
-- MAGIC > (`rtw_timeline`, and Gold features in Session 3) would silently lose the filtered rows.
-- MAGIC > Service/ETL identities are exempt from row-level security; masking only restricts analysts.
-- MAGIC
-- MAGIC Docs: [Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups)
-- MAGIC · [GRANT](https://learn.microsoft.com/azure/databricks/sql/language-manual/security-grant)
-- MAGIC · [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/)

-- COMMAND ----------

USE CATALOG state_fund_poc;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Grant analyst read access
-- MAGIC Analysts need `USE CATALOG` + `USE SCHEMA` to traverse, then `SELECT` on the Silver tables.
-- MAGIC The masks/row filter do the rest — no separate "secure view" required.

-- COMMAND ----------

GRANT USE CATALOG ON CATALOG state_fund_poc TO `analysts`;
GRANT USE SCHEMA  ON SCHEMA  silver          TO `analysts`;

GRANT SELECT ON TABLE silver.claims           TO `analysts`;
GRANT SELECT ON TABLE silver.employees        TO `analysts`;
GRANT SELECT ON TABLE silver.treatments       TO `analysts`;
GRANT SELECT ON TABLE silver.provider_billing TO `analysts`;
GRANT SELECT ON TABLE silver.rtw_timeline     TO `analysts`;
GRANT SELECT ON TABLE silver.adjuster_notes   TO `analysts`;

-- pii_authorized members get the same SELECT grants but see unmasked values / all rows.
GRANT USE CATALOG ON CATALOG state_fund_poc TO `pii_authorized`;
GRANT USE SCHEMA  ON SCHEMA  silver          TO `pii_authorized`;
GRANT SELECT ON TABLE silver.claims           TO `pii_authorized`;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Validate masking & row filtering
-- MAGIC Run the query below **as yourself** (a `pii_authorized` member → full values, all rows),
-- MAGIC then again as a non-authorized analyst (use **Run as** in a separate session, or have an
-- MAGIC analyst run it). Authorized users see real `ssn`/`dob` and `Southern CA` rows; analysts see
-- MAGIC `XXX-XX-####`, a Jan-1 birth year, and no `Southern CA` rows.

-- COMMAND ----------

SELECT claim_id, claimant_name, ssn, dob, region, claim_amount
FROM silver.claims
ORDER BY claim_id
LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Confirm the dirty rows were handled
-- MAGIC The poison row `CLM-00099` (future injury date, negative amount) and the duplicate
-- MAGIC `CLM-00006` should be gone, and invalid SSNs should be `NULL`.

-- COMMAND ----------

SELECT
  count(*)                                          AS total_claims,
  count(*) FILTER (WHERE claim_id = 'CLM-00099')    AS poison_rows,        -- expect 0
  count(*) FILTER (WHERE ssn IS NULL)               AS null_ssn_count,     -- invalid SSNs nulled
  count(*) FILTER (WHERE injury_date > current_date()) AS future_injuries  -- expect 0
FROM silver.claims;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Inspect the applied masks & filter
-- MAGIC `DESCRIBE EXTENDED` shows the column masks and row filter bound to `silver.claims`.

-- COMMAND ----------

DESCRIBE EXTENDED silver.claims;
