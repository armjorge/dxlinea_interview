import streamlit as st
import pandas as pd
import plotly.express as px
from snowflake.snowpark.context import get_active_session

# Page configuration
st.set_page_config(
    page_title="Sales Funnel Lead Distribution",
    page_icon="📊",
    layout="wide"
)

st.title("📊 Sales Funnel: Lead Status & Quarter Comparison")
st.markdown("Track lead distribution changes across quarters natively inside Snowflake using fixed pipeline categories.")

# --- DATA LOADING FROM SNOWFLAKE ---
@st.cache_data
def load_funnel_data():
    session = get_active_session()
    query = "SELECT * FROM DXLINEA_INTERVIEW.WRK_DXLINEA.wrk_sales_funnel"
    return session.sql(query).to_pandas()

try:
    df = load_funnel_data()
except Exception as e:
    st.error(f"Error loading data from Snowflake: {e}")
    st.stop()

# Snowflake returns uppercase column names by default; ensure normalization
df.columns = [c.upper() for c in df.columns]

# --- DEFINE FIXED CATEGORY ORDER ---
fixed_categories = ['MQL', 'New', 'Working', 'Nurture', 'Disqualified']

if 'LEAD_STATUS' in df.columns and 'LEAD_QUARTER' in df.columns:
    df['LEAD_STATUS'] = pd.Categorical(df['LEAD_STATUS'], categories=fixed_categories, ordered=True)

    # --- SIDEBAR CONTROLS ---
    st.sidebar.header("Filter Options")
    all_quarters = sorted(df['LEAD_QUARTER'].unique())

    selected_quarters = st.sidebar.multiselect(
        "Select Quarters to Compare:",
        options=all_quarters,
        default=all_quarters
    )

    filtered_df = df[df['LEAD_QUARTER'].isin(selected_quarters)]

    # --- MAIN DISPLAY AREA ---
    if selected_quarters:
        view_mode = st.radio(
            "Choose Analysis View:", 
            ["Matrix Table View", "Grouped Bar Chart View"], 
            horizontal=True
        )
        
        # Identify the value/percentage column dynamically
        val_col = 'STATUS_PRC' if 'STATUS_PRC' in filtered_df.columns else filtered_df.columns[-1]

        if view_mode == "Matrix Table View":
            st.subheader("Matrix Comparison: Lead Status % by Quarter")
            
            # Pivot table to structure rows as Statuses and columns as Quarters
            pivot_df = filtered_df.pivot(index='LEAD_STATUS', columns='LEAD_QUARTER', values=val_col)
            pivot_df = pivot_df.reindex(fixed_categories) # Enforce sort order
            
            st.dataframe(
                pivot_df.style.format("{:.2f}%").background_gradient(cmap="Blues", axis=1),
                use_container_width=True
            )
            
        else:
            st.subheader("Visual Distribution Comparison")
            
            # Plotly grouped bar chart with locked sort order
            fig = px.bar(
                filtered_df.sort_values('LEAD_STATUS'),
                x='LEAD_STATUS',
                y=val_col,
                color='LEAD_QUARTER',
                barmode='group',
                category_orders={'LEAD_STATUS': fixed_categories},
                labels={
                    'LEAD_STATUS': 'Lead Status Category', 
                    val_col: 'Percentage Share (%)', 
                    'LEAD_QUARTER': 'Quarter'
                },
                title="Quarter-over-Quarter Share Comparison Across Fixed Categories"
            )
            fig.update_layout(xaxis_title="Lead Status", yaxis_title="Percentage (%)")
            st.plotly_chart(fig, use_container_width=True)
            
    else:
        st.warning("⚠️ Please select at least one quarter from the sidebar to view the analysis.")
else:
    st.error("The expected columns 'LEAD_STATUS' and 'LEAD_QUARTER' were not found in your table schema.")
