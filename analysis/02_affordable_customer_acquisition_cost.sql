-- Question: how much can we afford to spend acquiring a customer?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/02_affordable_customer_acquisition_cost.sql"
--
-- A new logo is an account whose earliest Closed Won deal in this extract
-- is New Business, and whose account first_closed_won_date is empty or
-- falls inside the window (on or after 1 January 2025). Dates before 2025
-- are the workbook's marker for customers won in prior years. The account
-- is_customer flag is not used: hundreds of Closed Won accounts are still
-- flagged as prospects.
--
-- The ceiling is the landing deal's year-1 ARR. Paying more than that for
-- the logo produces a payback longer than 12 months even if delivery cost
-- is zero. There is no gross-margin or churn input to justify a lower
-- ceiling, so treat the average as the upper bound and the median as the
-- number to plan with. Enterprise deals pull the average up.
--
-- Fully loaded CAC divides every invoiced marketing dollar (including
-- programs that never produced a logo) by the new-logo count. It is on the
-- total row only. Segment rows are the cap for that segment, not a claim
-- that spend was tracked by segment.
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
first_won AS (
    SELECT *
    FROM won
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY account_id
        ORDER BY close_date, opportunity_id
    ) = 1
),
new_logo AS (
    SELECT
        f.account_id,
        f.sales_segment,
        f.arr_usd AS landing_arr_usd,
        f.source_lead_id IS NOT NULL AS marketing_sourced
    FROM first_won AS f
    JOIN account_raw AS a
        USING (account_id)
    WHERE f.opportunity_type = 'New Business'
      AND (
          a.first_closed_won_date IS NULL
          OR CAST(a.first_closed_won_date AS DATE) >= DATE '2025-01-01'
      )
),
logo_stats AS (
    SELECT
        COALESCE(sales_segment, '(all new logos)') AS sales_segment,
        COUNT(*) AS new_logos,
        COUNT(*) FILTER (WHERE marketing_sourced) AS marketing_sourced_logos,
        AVG(landing_arr_usd) AS avg_landing_arr_usd,
        MEDIAN(landing_arr_usd) AS median_landing_arr_usd
    FROM new_logo
    GROUP BY GROUPING SETS ((sales_segment), ())
),
spend AS (
    SELECT SUM(spend_usd) AS marketing_spend_usd
    FROM campaign
)
SELECT
    g.sales_segment,
    g.new_logos,
    g.marketing_sourced_logos,
    ROUND(g.avg_landing_arr_usd, 2) AS allowable_cac_12_month_payback,
    ROUND(g.median_landing_arr_usd, 2) AS planning_cac_at_median_deal,
    CASE
        WHEN g.sales_segment = '(all new logos)'
            THEN ROUND(s.marketing_spend_usd / g.new_logos, 2)
    END AS fully_loaded_cac,
    CASE
        WHEN g.sales_segment = '(all new logos)'
            THEN ROUND(
                (s.marketing_spend_usd / g.new_logos) / (g.avg_landing_arr_usd / 12.0),
                1
            )
    END AS fully_loaded_payback_months,
    CASE
        WHEN g.sales_segment = '(all new logos)'
            THEN ROUND(g.avg_landing_arr_usd - s.marketing_spend_usd / g.new_logos, 2)
    END AS headroom_against_average_deal
FROM logo_stats AS g
CROSS JOIN spend AS s
ORDER BY
    CASE g.sales_segment
        WHEN 'Enterprise' THEN 1
        WHEN 'Mid-Market' THEN 2
        WHEN 'SMB' THEN 3
        ELSE 4
    END;
