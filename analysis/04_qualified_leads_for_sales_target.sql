-- Question: how many qualified leads are required to hit a sales target?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/04_qualified_leads_for_sales_target.sql"
--
-- Change the target in the params CTE. The default is 1,000,000 of ARR.
-- The segment rows answer a different question: how many 2025-style MQLs
-- it would take if the WHOLE target were generated from that segment.
-- Do not add the segment rows to the total row.
--
-- Qualified means MQL (status or mql_date). The rate is taken from MQLs
-- created in 2025 only. The longest observed Closed Won cycle is 209 days,
-- so a lead created on 31 December 2025 could have closed before the
-- 8 September 2026 extract. The 2026 cohort is still inside that window
-- and is excluded.
--
-- Yield = Closed Won ARR on opportunities whose source lead is in that
-- MQL set, divided by the MQL count. Leads with no win contribute zero.
WITH
campaign_raw AS (
    SELECT *
    FROM read_duckdb(
        'analysis/delinea.duckdb',
        schema_name = 'main',
        table_name = 'mkt_campaign'
    )
),

lead_raw AS (
    SELECT *
    FROM read_duckdb(
        'analysis/delinea.duckdb',
        schema_name = 'main',
        table_name = 'mkt_lead'
    )
),

touch_raw AS (
    SELECT *
    FROM read_duckdb(
        'analysis/delinea.duckdb',
        schema_name = 'main',
        table_name = 'mkt_touchpoint'
    )
),

opportunity_raw AS (
    SELECT *
    FROM read_duckdb(
        'analysis/delinea.duckdb',
        schema_name = 'main',
        table_name = 'sfdc_opportunity'
    )
),

account_raw AS (
    SELECT *
    FROM read_duckdb(
        'analysis/delinea.duckdb',
        schema_name = 'main',
        table_name = 'sfdc_account'
    )
),
campaign_alias AS (
    -- Same name, quarter, and invoiced amount as the canonical campaign,
    -- with source-lead credit staying on the canonical id. Counting both
    -- rows would book the same invoice twice. Touchpoints on the alias are
    -- kept and folded onto the canonical id below.
    SELECT * FROM (VALUES
        ('CMP-9801', 'CMP-1134'),
        ('CMP-9802', 'CMP-1177'),
        ('CMP-9803', 'CMP-1184')
    ) AS v(alias_id, campaign_id)
),
campaign AS (
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,
        c.sub_channel,
        c.program_type,
        c.region AS campaign_region,
        c.target_segment,
        c.fiscal_quarter,
        CAST(c.start_date AS DATE) AS start_date,
        CAST(c.end_date AS DATE) AS end_date,
        c.currency_code,
        c.fx_rate_to_usd,
        c.actual_spend_local * c.fx_rate_to_usd AS spend_usd,
        -- Extract date is 8 September 2026. Median sales cycle is ~110 days
        -- and the 75th percentile is 157 days, so a campaign that ended on
        -- 31 March 2026 has had long enough for a typical deal to close.
        -- 2026 Q2 and Q3 are still inside that lag. Their low ROI is
        -- censored, not evidence that the spend failed.
        CAST(c.end_date AS DATE) <= DATE '2026-03-31' AS is_mature
    FROM campaign_raw AS c
    WHERE c.campaign_id NOT IN (SELECT alias_id FROM campaign_alias)
),
lead_alias AS (
    -- 1,457 ids shaped LEA-9xxxxxx repeat a shorter lead: same email,
    -- account, created date, source campaign, and status. Counting both
    -- doubles the funnel. Opportunities and touchpoints are remapped to
    -- the short id. The extra touch rows are a second slice of the same
    -- person's journey, so they are kept.
    SELECT
        duplicate.lead_id AS alias_id,
        canonical.lead_id
    FROM lead_raw AS duplicate
    JOIN lead_raw AS canonical
        ON duplicate.email = canonical.email
    WHERE length(duplicate.lead_id) > 10
      AND length(canonical.lead_id) = 10
    UNION ALL
    SELECT lead_id AS alias_id, lead_id
    FROM lead_raw
    WHERE length(lead_id) = 10
),
lead AS (
    SELECT
        l.lead_id,
        l.account_id,
        l.email,
        CAST(l.created_date AS DATE) AS created_date,
        COALESCE(alias.campaign_id, l.source_campaign_id) AS source_campaign_id,
        l.lead_status,
        CAST(l.mql_date AS DATE) AS mql_date,
        l.sales_segment,
        l.region,
        l.job_level,
        -- Status and the MQL date disagree on 220 rows (status is MQL and
        -- the date is empty). Either signal is enough. Disqualified leads
        -- never carry an MQL status or an MQL date.
        (l.lead_status = 'MQL' OR l.mql_date IS NOT NULL) AS is_mql
    FROM lead_raw AS l
    LEFT JOIN campaign_alias AS alias
        ON l.source_campaign_id = alias.alias_id
    WHERE length(l.lead_id) = 10
),
won AS (
    -- stage_name is the source of truth. is_won is 1 on four open
    -- Negotiation deals and 0 on six Closed Won deals.
    -- One Closed Won row has a null arr_usd; ARR is TCV divided by term.
    SELECT
        o.opportunity_id,
        o.account_id,
        mapped.lead_id AS source_lead_id,
        COALESCE(alias.campaign_id, o.primary_campaign_id) AS primary_campaign_id,
        o.opportunity_type,
        o.product_line,
        o.sales_segment,
        o.region,
        CAST(o.created_date AS DATE) AS created_date,
        CAST(o.close_date AS DATE) AS close_date,
        o.term_months,
        COALESCE(o.arr_usd, o.amount_usd * 12.0 / o.term_months) AS arr_usd
    FROM opportunity_raw AS o
    LEFT JOIN lead_alias AS mapped
        ON o.source_lead_id = mapped.alias_id
    LEFT JOIN campaign_alias AS alias
        ON o.primary_campaign_id = alias.alias_id
    WHERE o.stage_name = 'Closed Won'
),
params AS (
    SELECT 1000000.0::DOUBLE AS target_arr_usd
),
mql_2025 AS (
    SELECT lead_id, sales_segment
    FROM lead
    WHERE is_mql
      AND created_date >= DATE '2025-01-01'
      AND created_date < DATE '2026-01-01'
),
mql_yield AS (
    SELECT
        m.sales_segment,
        m.lead_id,
        COALESCE(SUM(w.arr_usd), 0) AS won_arr_usd
    FROM mql_2025 AS m
    LEFT JOIN won AS w
        ON w.source_lead_id = m.lead_id
    GROUP BY m.sales_segment, m.lead_id
),
stats AS (
    SELECT
        COALESCE(sales_segment, '(all segments)') AS sales_segment,
        COUNT(*) AS mqls_2025,
        COUNT(*) FILTER (WHERE won_arr_usd > 0) AS mqls_that_closed_won,
        SUM(won_arr_usd) AS closed_won_arr_usd,
        SUM(won_arr_usd) / COUNT(*) AS arr_per_mql
    FROM mql_yield
    GROUP BY GROUPING SETS ((sales_segment), ())
)
SELECT
    s.sales_segment,
    s.mqls_2025,
    s.mqls_that_closed_won,
    ROUND(s.mqls_that_closed_won * 1.0 / s.mqls_2025, 4) AS mql_to_won_rate,
    ROUND(s.closed_won_arr_usd, 2) AS closed_won_arr_usd,
    ROUND(s.arr_per_mql, 2) AS arr_usd_per_mql,
    ROUND(p.target_arr_usd, 2) AS target_arr_usd,
    CAST(CEIL(p.target_arr_usd / NULLIF(s.arr_per_mql, 0)) AS INTEGER) AS mqls_required
FROM stats AS s
CROSS JOIN params AS p
ORDER BY
    CASE s.sales_segment
        WHEN 'Enterprise' THEN 1
        WHEN 'Mid-Market' THEN 2
        WHEN 'SMB' THEN 3
        ELSE 4
    END;
