-- Question: what advertising budget maximizes profitability rather than
-- sales volume?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/03_optimal_advertising_budget.sql"
--
-- A mature campaign (ended on or before 31 March 2026) stays in the budget
-- when its marketing-credited ARR at least covers its invoiced spend.
-- Below that line, the next dollar buys less than a dollar of year-1 ARR,
-- so sales can still be positive while contribution falls. Those dollars
-- are the cut.
--
-- Campaigns that ended after 31 March 2026 are held at their current spend.
-- The extract is 8 September 2026 and a typical deal takes about five
-- months to close, so judging 2026 Q2 and Q3 on closed ARR would punish
-- lag, not waste.
--
-- Optimal spend = profitable mature spend + all immature spend.
-- Actual spend = every known invoice. Two Paid Social campaigns have a
-- null actual and are in neither number.
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
touch AS (
    SELECT
        mapped.lead_id,
        COALESCE(alias.campaign_id, t.campaign_id) AS campaign_id,
        CAST(t.touch_date AS DATE) AS touch_date,
        t.touch_type,
        t.attribution_weight_first,
        t.attribution_weight_last
    FROM touch_raw AS t
    JOIN lead_alias AS mapped
        ON t.lead_id = mapped.alias_id
    LEFT JOIN campaign_alias AS alias
        ON t.campaign_id = alias.alias_id
),
touch_counts AS (
    SELECT lead_id, COUNT(*) AS n_touches
    FROM touch
    GROUP BY lead_id
),
-- Last-touch weights are not usable raw: 1,396 leads sum to 0 and 1,140
-- sum to between 2 and 5. First-touch weights do sum to 1 before the
-- duplicate-lead merge; after the merge they can exceed 1, so both flags
-- are renormalized per lead wherever a method uses them.
touch_flags AS (
    SELECT
        lead_id,
        campaign_id,
        attribution_weight_first,
        attribution_weight_last,
        SUM(attribution_weight_first) OVER (PARTITION BY lead_id) AS first_sum,
        SUM(attribution_weight_last) OVER (PARTITION BY lead_id) AS last_sum
    FROM touch
),
opp_credit AS (
    -- Even weight across observed touches. Every real interaction splits
    -- the deal. This is the working attribution model for the other questions.
    SELECT
        w.opportunity_id,
        t.campaign_id,
        1.0 / c.n_touches AS weight
    FROM won AS w
    JOIN touch AS t
        ON w.source_lead_id = t.lead_id
    JOIN touch_counts AS c
        ON w.source_lead_id = c.lead_id
    UNION ALL
    -- About 28% of leads have no touchpoint row. Fall back to the platform's
    -- source campaign rather than dropping the deal. Sales-sourced wins have
    -- no lead and stay outside marketing credit.
    SELECT
        w.opportunity_id,
        l.source_campaign_id AS campaign_id,
        1.0 AS weight
    FROM won AS w
    JOIN lead AS l
        ON w.source_lead_id = l.lead_id
    LEFT JOIN touch_counts AS c
        ON w.source_lead_id = c.lead_id
    WHERE c.lead_id IS NULL
      AND l.source_campaign_id IS NOT NULL
),
credited AS (
    SELECT
        oc.campaign_id,
        w.opportunity_id,
        w.product_line,
        w.region,
        w.sales_segment,
        w.opportunity_type,
        w.account_id,
        w.arr_usd * oc.weight AS arr_credit
    FROM opp_credit AS oc
    JOIN won AS w
        USING (opportunity_id)
),
campaign_credit AS (
    SELECT campaign_id, SUM(arr_credit) AS arr_credit
    FROM credited
    GROUP BY campaign_id
),
campaign_econ AS (
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,
        c.program_type,
        c.campaign_region,
        c.fiscal_quarter,
        c.end_date,
        c.is_mature,
        c.spend_usd,
        COALESCE(a.arr_credit, 0) AS arr_credit
    FROM campaign AS c
    LEFT JOIN campaign_credit AS a
        USING (campaign_id)
),
classified AS (
    SELECT
        channel,
        is_mature,
        spend_usd,
        arr_credit,
        CASE
            WHEN spend_usd IS NULL THEN 'unknown_invoice'
            WHEN NOT is_mature THEN 'hold_immature'
            WHEN arr_credit >= spend_usd THEN 'keep_profitable'
            ELSE 'cut_unprofitable'
        END AS decision
    FROM campaign_econ
),
rolled AS (
    SELECT
        COALESCE(channel, '(all channels)') AS channel,
        SUM(spend_usd) FILTER (WHERE decision = 'keep_profitable') AS profitable_mature_spend_usd,
        SUM(arr_credit) FILTER (WHERE decision = 'keep_profitable') AS profitable_mature_arr_usd,
        SUM(spend_usd) FILTER (WHERE decision = 'cut_unprofitable') AS cut_spend_usd,
        SUM(arr_credit) FILTER (WHERE decision = 'cut_unprofitable') AS arr_given_up_usd,
        SUM(spend_usd) FILTER (WHERE decision = 'hold_immature') AS immature_spend_held_usd,
        SUM(arr_credit) FILTER (WHERE decision = 'hold_immature') AS immature_arr_observed_usd,
        SUM(spend_usd) FILTER (WHERE decision <> 'unknown_invoice') AS actual_spend_usd,
        COUNT(*) FILTER (WHERE decision = 'unknown_invoice') AS campaigns_missing_actual_spend
    FROM classified
    GROUP BY GROUPING SETS ((channel), ())
)
SELECT
    channel,
    ROUND(profitable_mature_spend_usd, 2) AS profitable_mature_spend_usd,
    ROUND(cut_spend_usd, 2) AS spend_to_remove_usd,
    ROUND(arr_given_up_usd, 2) AS arr_given_up_if_removed_usd,
    ROUND(immature_spend_held_usd, 2) AS immature_spend_held_usd,
    ROUND(immature_arr_observed_usd, 2) AS immature_arr_observed_so_far_usd,
    ROUND(
        COALESCE(profitable_mature_spend_usd, 0) + COALESCE(immature_spend_held_usd, 0),
        2
    ) AS optimal_spend_usd,
    ROUND(actual_spend_usd, 2) AS actual_spend_usd,
    campaigns_missing_actual_spend
FROM rolled
ORDER BY
    CASE WHEN channel = '(all channels)' THEN 1 ELSE 0 END,
    spend_to_remove_usd DESC NULLS LAST,
    channel;
