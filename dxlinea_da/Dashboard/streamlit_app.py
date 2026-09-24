

import os
import pathlib
import pandas as pd
import plotly.express as px
import plotly.graph_objects as rx
import streamlit as st

# Set Streamlit Page Configuration
st.set_page_config(
    page_title="DXLinea - Executive Marketing & Pipeline Analysis",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ------------------------------------------------------------------------------
# 1. HYBRID DATA LOADER (Snowflake + Local CSV Fallback)
# ------------------------------------------------------------------------------
@st.cache_data(show_spinner="Loading data...")
def load_data():
    use_snowflake = False
    session = None

    # Check for Snowflake in Snowpark / Streamlit in Snowflake environment
    try:
        from snowflake.snowpark.context import get_active_session

        session = get_active_session()
        use_snowflake = True
    except Exception:
        use_snowflake = False

    if use_snowflake and session is not None:
        # Load directly from Snowflake tables
        query_funnel = "SELECT * FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_SALES_FUNNEL"
        query_opps = (
            "SELECT * FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_SFDC_OPPORTUNITIES_Q"
        )

        df_funnel = session.sql(query_funnel).to_pandas()
        df_opps = session.sql(query_opps).to_pandas()
    else:
        # Fallback to local CSV files (Navigating 3 levels up from Dashboard/ to src_files/)
        current_dir = pathlib.Path(__file__).parent.resolve()
        src_dir = (current_dir / ".." / ".." / ".." / "src_files").resolve()

        csv_funnel_path = src_dir / "wrk_sales_funnel.csv"
        csv_opps_path = src_dir / "wrk_sfdc_opportunities_q.csv"

        # Alternative relative fallback if folder tree varies slightly
        if not csv_funnel_path.exists():
            csv_funnel_path = "src_files/wrk_sales_funnel.csv"
            csv_opps_path = "src_files/wrk_sfdc_opportunities_q.csv"

        df_funnel = pd.read_csv(csv_funnel_path)
        df_opps = pd.read_csv(csv_opps_path)

    # Standardize column headers to uppercase
    df_funnel.columns = [c.upper() for c in df_funnel.columns]
    df_opps.columns = [c.upper() for c in df_opps.columns]

    return df_funnel, df_opps


df_funnel, df_opps = load_data()

# ------------------------------------------------------------------------------
# 2. NAVIGATION & SIDEBAR FILTERS
# ------------------------------------------------------------------------------
st.sidebar.title("DXLinea Analytics")
st.sidebar.caption("Executive Insights for CFO & CRO Briefing")

page = st.sidebar.radio(
    "Navigation",
    ["Overview & Spend Efficiency", "Pipeline & Lead Conversion Diagnostics"],
)

quarters_available = sorted(df_funnel["LEAD_QUARTER"].unique().tolist())
selected_quarters = st.sidebar.multiselect(
    "Filter Quarters",
    quarters_available,
    default=[q for q in quarters_available if "2026" in str(q)],
)

if selected_quarters:
    f_funnel = df_funnel[df_funnel["LEAD_QUARTER"].isin(selected_quarters)]
    f_opps = df_opps[df_opps["CREATION_QUARTER"].isin(selected_quarters)]
else:
    f_funnel = df_funnel.copy()
    f_opps = df_opps.copy()

# ------------------------------------------------------------------------------
# PAGE 1: OVERVIEW & SPEND EFFICIENCY
# ------------------------------------------------------------------------------
if page == "Overview & Spend Efficiency":
    st.title("💰 Marketing Spend & Lead Efficiency Overview")
    st.markdown(
        "Executive scorecard evaluating program spend, MQL trends, and cost efficiency across quarters."
    )
    st.divider()

    # SECTION 1: DISTINCT SPEND SCORECARDS
    st.subheader("1. Quarter Financial Scorecards")

    # Aggregate distinct spend per quarter to avoid double counting across status rows
    df_spend_q = (
        f_funnel.groupby("LEAD_QUARTER")
        .agg(
            ACTUAL_SPEND=("ACTUAL_SPEND_USD", "max"),
            PLANNED_SPEND=("PLANNED_SPEND_USD", "max"),
            AVG_LEAD_COST=("LEAD_COST", "mean"),
            TOTAL_LEADS=("QUARTER_LEADS", "max"),
        )
        .reset_index()
    )

    cols = st.columns(min(len(df_spend_q), 4))
    for i, (_, row) in enumerate(df_spend_q.iterrows()):
        col_idx = i % 4
        with cols[col_idx]:
            quarter = row["LEAD_QUARTER"]
            actual_spend = row["ACTUAL_SPEND"]
            planned_spend = row["PLANNED_SPEND"]
            variance = actual_spend - planned_spend
            cost_per_lead = row["AVG_LEAD_COST"]

            st.metric(
                label=f"Quarter {quarter} Spend",
                value=f"${actual_spend:,.0f}",
                delta=f"${variance:,.0f} vs Plan" if planned_spend else None,
                delta_color="inverse",
            )
            st.caption(
                f"**Planned:** ${planned_spend:,.0f} | **Avg Cost/Lead:** ${cost_per_lead:,.2f}"
            )

    st.divider()

    # SECTION 2: PLANNED VS ACTUAL SPEND & LEAD VOLUMES
    st.subheader("2. Planned vs. Actual Spend Breakdown")

    col_chart1, col_chart2 = st.columns(2)

    with col_chart1:
        fig_spend = px.bar(
            df_spend_q,
            x="LEAD_QUARTER",
            y=["PLANNED_SPEND", "ACTUAL_SPEND"],
            barmode="group",
            title="Planned vs. Actual Spend (USD)",
            labels={"value": "Spend (USD)", "LEAD_QUARTER": "Quarter"},
            color_discrete_sequence=["#94A3B8", "#2563EB"],
        )
        fig_spend.update_layout(legend_title_text="Category")
        st.plotly_chart(fig_spend, use_container_width=True)

    with col_chart2:
        df_status = (
            f_funnel.groupby(["LEAD_QUARTER", "LEAD_STATUS"])["LEADS_QTY"]
            .sum()
            .reset_index()
        )
        fig_status = px.bar(
            df_status,
            x="LEAD_QUARTER",
            y="LEADS_QTY",
            color="LEAD_STATUS",
            title="Lead Volume Distribution by Status",
            labels={"LEADS_QTY": "Number of Leads", "LEAD_QUARTER": "Quarter"},
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        st.plotly_chart(fig_status, use_container_width=True)

    # SECTION 3: DATA TABLE DETAILS
    st.subheader("3. Lead Funnel Detailed Summary")
    st.dataframe(
        f_funnel[
            [
                "LEAD_QUARTER",
                "LEAD_STATUS",
                "LEADS_QTY",
                "QUARTER_LEADS",
                "STATUS_PRC",
                "PLANNED_SPEND_USD",
                "ACTUAL_SPEND_USD",
                "LEAD_COST",
            ]
        ],
        use_container_width=True,
    )

# ------------------------------------------------------------------------------
# PAGE 2: PIPELINE & CONVERSION DIAGNOSTICS
# ------------------------------------------------------------------------------
elif page == "Pipeline & Lead Conversion Diagnostics":
    st.title("🎯 Pipeline & Lead Conversion Diagnostics")
    st.markdown(
        "Diagnostic findings on pipeline generation, sales cycle lag, and cohort efficiency trends."
    )
    st.divider()

    # SECTION 1: EXECUTIVE FINDINGS
    st.subheader("Executive Diagnostic Summary for CFO & CRO")
    c1, c2, c3 = st.columns(3)

    with c1:
        st.info("💡 **1. MQL Growth Illusion**")
        st.write(
            "Top-of-funnel MQLs are up >30% YoY with lower CPL, but opportunity creation dropped **37% in Q3** (357 → 225). Marketing is generating high volume from lower-intent leads."
        )

    with c2:
        st.warning("⚠️ **2. Cohort Quality Decay**")
        st.write(
            "Win rate on resolved deals decayed **17% relative** (27.2% in Q1 → 22.6% in Q2). Simultaneously, average deal size for Won deals fell **31.6%** ($90.7k → $62.1k)."
        )

    with c3:
        st.success("🎯 **3. Q4 $1.5M Spend Reallocation**")
        st.write(
            "Stop top-of-funnel high-volume lead programs. Reallocate $1.5M into **Mid-Funnel Acceleration** to convert **$11.8M ARR currently sitting in Proposal and Negotiation**."
        )

    st.divider()

    # SECTION 2: OPPORTUNITY & ARR BY STAGE
    st.subheader("Pipeline & ARR Distribution by Opportunity Stage")

    col_p1, col_p2 = st.columns(2)

    with col_p1:
        df_opp_stage = (
            f_opps.groupby(["CREATION_QUARTER", "STAGE_NAME"])[
                "Q_STAGE_OPPORTUNITIES"
            ]
            .sum()
            .reset_index()
        )
        fig_opps = px.bar(
            df_opp_stage,
            x="CREATION_QUARTER",
            y="Q_STAGE_OPPORTUNITIES",
            color="STAGE_NAME",
            title="Opportunity Count by Creation Quarter & Stage",
            color_discrete_sequence=px.colors.qualitative.Pastel,
        )
        st.plotly_chart(fig_opps, use_container_width=True)

    with col_p2:
        df_arr_stage = (
            f_opps.groupby(["CREATION_QUARTER", "STAGE_NAME"])["YEAR_AMOUNT"]
            .sum()
            .reset_index()
        )
        fig_arr = px.bar(
            df_arr_stage,
            x="CREATION_QUARTER",
            y="YEAR_AMOUNT",
            color="STAGE_NAME",
            title="Pipeline ARR ($) by Creation Quarter & Stage",
            labels={"YEAR_AMOUNT": "ARR (USD)"},
            color_discrete_sequence=px.colors.qualitative.Safe,
        )
        st.plotly_chart(fig_arr, use_container_width=True)

    # SECTION 3: COHORT EFFICIENCY TABLE
    st.subheader("Cohort Resolution Performance (Q1 vs. Q2 Baseline)")

    # Diagnostic Table
    summary_data = {
        "Metric": [
            "Resolved Deals",
            "Resolved Win Rate (%)",
            "Avg ARR per Won Deal ($)",
            "Closed-Won ARR Realized ($M)",
        ],
        "2026Q1 Cohort": ["286", "27.27%", "$90,740", "$7.08M"],
        "2026Q2 Cohort": ["159", "22.64%", "$62,059", "$2.23M"],
        "Impact / Variance": [
            "--",
            "-4.6 pp (-17.0% decay)",
            "-31.6% deal size",
            "Heavy lag / drop",
        ],
    }
    df_diag = pd.DataFrame(summary_data)
    st.table(df_diag)
