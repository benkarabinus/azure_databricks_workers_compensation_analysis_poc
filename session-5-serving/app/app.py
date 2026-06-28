import os

import streamlit as st
from databricks import sql
from databricks.sdk.core import Config

st.set_page_config(page_title="Fraud Triage Queue", page_icon="🔎", layout="wide")

CATALOG = "state_fund_poc"
SCORES_TABLE = f"{CATALOG}.gold.fraud_scores"

# Inside Databricks Apps, Config() authenticates with the app's service principal.
cfg = Config()
WAREHOUSE_ID = os.environ.get("DATABRICKS_WAREHOUSE_ID")


@st.cache_resource
def get_connection():
    return sql.connect(
        server_hostname=cfg.host,
        http_path=f"/sql/1.0/warehouses/{WAREHOUSE_ID}",
        credentials_provider=lambda: cfg.authenticate,
    )


@st.cache_data(ttl=60)
def load_scores():
    query = f"""
        SELECT claim_id, fraud_risk_score, risk_tier, top_contributing_factor,
               is_fraud_actual, scored_at
        FROM {SCORES_TABLE}
        ORDER BY fraud_risk_score DESC
    """
    with get_connection().cursor() as cursor:
        cursor.execute(query)
        return cursor.fetchall_arrow().to_pandas()


st.title("🔎 Fraud Investigation Triage Queue")
st.caption(
    "Model-ranked claims for SIU review — triage acceleration, not an automated fraud decision."
)

if not WAREHOUSE_ID:
    st.error(
        "No SQL warehouse configured. Add a **SQL warehouse** resource to this app "
        "(it injects `DATABRICKS_WAREHOUSE_ID`)."
    )
    st.stop()

df = load_scores()

tiers = st.multiselect("Risk tier", ["High", "Medium", "Low"], default=["High", "Medium"])
view = df[df["risk_tier"].isin(tiers)] if tiers else df

col1, col2, col3 = st.columns(3)
col1.metric("Claims in queue", len(view))
col2.metric("High risk", int((view["risk_tier"] == "High").sum()))
col3.metric("Avg risk score", round(view["fraud_risk_score"].mean(), 3) if len(view) else 0.0)

st.dataframe(view, use_container_width=True, hide_index=True)

selected = st.selectbox("Inspect a claim", view["claim_id"].tolist() if len(view) else [])
if selected:
    row = view[view["claim_id"] == selected].iloc[0]
    st.subheader(f"Claim {selected}")
    st.write(f"**Risk score:** {row['fraud_risk_score']} · **Tier:** {row['risk_tier']}")
    st.write(f"**Top contributing factor:** {row['top_contributing_factor']}")
    st.info(
        "Extend this panel with Vector Search 'similar past claims' "
        "(see vector_search_setup.py)."
    )
