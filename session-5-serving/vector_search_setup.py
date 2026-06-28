# Databricks notebook source
# MAGIC %md
# MAGIC # Session 5 — Vector Search (similar-claim lookup)
# MAGIC
# MAGIC Builds a Databricks **AI Search** (Vector Search) index over the **redacted** adjuster notes so
# MAGIC the triage app can surface *"similar past claims"* for an investigator. Steps: create a
# MAGIC Change-Data-Feed source table from `silver.adjuster_notes`, create an AI Search endpoint, create
# MAGIC a delta-sync index with Databricks-computed embeddings, then run a similarity query.
# MAGIC
# MAGIC > Requires AI Search / Vector Search to be available in your region, and an embedding endpoint
# MAGIC > (`databricks-gte-large-en`). The notes are already PII-redacted (Session 2), so nothing
# MAGIC > sensitive is embedded.
# MAGIC
# MAGIC **Docs:** [Create AI Search endpoints and indexes](https://learn.microsoft.com/azure/databricks/ai-search/create-ai-search)
# MAGIC · [Query an AI Search index](https://learn.microsoft.com/azure/databricks/ai-search/query-ai-search)
# MAGIC · [Change data feed](https://learn.microsoft.com/azure/databricks/delta/delta-change-data-feed)

# COMMAND ----------

# DBTITLE 1,Install dependencies
# MAGIC %pip install databricks-ai-search -q
# MAGIC %restart_python

# COMMAND ----------

CATALOG = "state_fund_poc"
SOURCE_TABLE = f"{CATALOG}.gold.claim_notes"          # CDF-enabled source for the index
ENDPOINT = "state_fund_poc_vs"
INDEX = f"{CATALOG}.gold.claim_notes_index"
EMBED_ENDPOINT = "databricks-gte-large-en"            # pay-per-token embedding model

# COMMAND ----------

# DBTITLE 1,Create the Change-Data-Feed source table
# One row per claim note (PII already redacted in Session 2). claim_id is the primary key.
spark.sql(f"""
  CREATE OR REPLACE TABLE {SOURCE_TABLE}
  TBLPROPERTIES (delta.enableChangeDataFeed = true)
  AS SELECT claim_id, note_text_redacted, note_category
  FROM {CATALOG}.silver.adjuster_notes
  WHERE note_text_redacted IS NOT NULL
""")
print("Created", SOURCE_TABLE)

# COMMAND ----------

# DBTITLE 1,Create the AI Search endpoint
# Older workspaces: `from databricks.vector_search.client import VectorSearchClient` /
# `VectorSearchClient()` exposes the same create_endpoint / create_delta_sync_index / similarity_search.
from databricks.ai_search.client import AISearchClient

client = AISearchClient()
client.create_endpoint(name=ENDPOINT, endpoint_type="STANDARD")
print(f"Requested endpoint '{ENDPOINT}'. Wait until it shows ONLINE (Compute ▸ AI Search) before the next cell.")

# COMMAND ----------

# DBTITLE 1,Create the delta-sync index (Databricks-computed embeddings)
index = client.create_delta_sync_index(
    endpoint_name=ENDPOINT,
    source_table_name=SOURCE_TABLE,
    index_name=INDEX,
    pipeline_type="TRIGGERED",
    primary_key="claim_id",
    embedding_source_column="note_text_redacted",
    embedding_model_endpoint_name=EMBED_ENDPOINT,
    columns_to_sync=["claim_id", "note_text_redacted", "note_category"],
)
print("Created index", INDEX)

# COMMAND ----------

# DBTITLE 1,Sync and query
index = client.get_index(index_name=INDEX)
index.sync()  # TRIGGERED index: run a sync to populate it (wait until it finishes in the UI)

results = index.similarity_search(
    query_text="multiple providers billing the same week, claimant uncooperative, treatment far from home",
    columns=["claim_id", "note_category", "note_text_redacted"],
    num_results=5,
)
print(results)
