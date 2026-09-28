# DXLinea - Marketing & Sales Funnel Analytics

This repository contains the end-to-end data engineering and analytics pipeline for DXLinea. It covers data extraction, Snowflake staging, dbt modeling, and an executive Streamlit dashboard designed to evaluate marketing spend efficiency, lead conversion, and sales pipeline performance.

##  🛠️ Project Architecture & Repository Structure

```
├── Plan.md                    # Strategy for loading data into Snowflake for analytics
├── analytics lifecycle.md     # Main analytical path, diagnostic framework, and findings
├── data_extraction/           # Python scripts to transform raw .xlsx source files into Parquet
├── src_files/                 # Local directory for raw source CSVs/Parquet (Git-ignored)
├── dxlinea_project/           # dbt project with transformations and analytics models
├── dxlinea_da/                # Analytical SQL queries and Streamlit Dashboard
│   └── Dashboard/
│       └── streamlit_app.py   # Executive Streamlit Dashboard
└── snowflake_objects/         # DDL scripts for Snowflake database, schemas, and stages
```



## 2. dbt Models Setup

Ensure dbt dependencies are installed before running or compiling models:

```
cd dxlinea_project
dbt deps
dbt build
```

## 📊 Running the Dashboard

The executive dashboard automatically detects your environment:
Local Mode: Loads local fallback CSV files from src_files/.
Snowflake Mode: Queries live analytical models (WRK_SALES_FUNNEL and WRK_SFDC_OPPORTUNITIES_Q) when run inside Streamlit in Snowflake.
To launch the dashboard locally:



## 📋 Key Analytical Scope

The analysis addresses three core executive objectives for the Q4 CFO/CRO briefing:
MQL Growth vs. Pipeline Quality: Dissecting the 30% YoY MQL growth against true opportunity conversion.
Sales Cycle Lag & Cohort Performance: Analyzing the ~110-day median sales cycle and tracking win rates and deal sizes across Q1, Q2, and Q3 cohorts.
Spend Reallocation Strategy: Recommendations for reallocating top-of-funnel program spend into mid-funnel deal acceleration.