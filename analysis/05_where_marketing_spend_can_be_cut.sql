-- Question: where are we overspending, and how much marketing can we cut
-- without materially affecting sales?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/05_where_marketing_spend_can_be_cut.sql"
--
-- Only mature campaigns are eligible to cut (ended on or before 31 March
-- 2026). Two scenarios:
--   roi_below_1     removes every mature campaign whose credited ARR does
--                   not cover its spend. This maximizes contribution. Sales
--                   do move, by the credited ARR on those campaigns.
--   roi_below_0_25  removes only the mature campaigns returning less than
--                   25 cents of ARR per dollar. This is the cut that leaves
--                   sales almost unchanged.
--
-- "Material" is defined here as forfeited credited ARR above 2% of all
-- Closed Won ARR. The flag is on each row so a channel can be immaterial
-- even when the combined roi_below_1 cut is not.
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
totals AS (
    SELECT
        (SELECT SUM(arr_usd) FROM won) AS closed_won_arr_usd,
        (SELECT SUM(arr_credit) FROM campaign_econ WHERE is_mature) AS mature_credited_arr_usd
),
cuts AS (
    SELECT 'roi_below_1' AS scenario, channel, spend_usd, arr_credit
    FROM campaign_econ
    WHERE is_mature
      AND spend_usd IS NOT NULL
      AND arr_credit < spend_usd
    UNION ALL
    SELECT 'roi_below_0_25' AS scenario, channel, spend_usd, arr_credit
    FROM campaign_econ
    WHERE is_mature
      AND spend_usd IS NOT NULL
      AND spend_usd > 0
      AND arr_credit / spend_usd < 0.25
),
rolled AS (
    SELECT
        scenario,
        COALESCE(channel, '(all channels)') AS channel,
        COUNT(*) AS campaigns_to_cut,
        SUM(spend_usd) AS spend_removed_usd,
        SUM(arr_credit) AS arr_forfeited_usd
    FROM cuts
    GROUP BY GROUPING SETS ((scenario, channel), (scenario))
)
SELECT
    r.scenario,
    r.channel,
    r.campaigns_to_cut,
    ROUND(r.spend_removed_usd, 2) AS spend_removed_usd,
    ROUND(r.arr_forfeited_usd, 2) AS arr_forfeited_usd,
    ROUND(r.spend_removed_usd - r.arr_forfeited_usd, 2) AS contribution_regained_usd,
    ROUND(r.arr_forfeited_usd / t.closed_won_arr_usd, 4) AS forfeited_share_of_closed_won_arr,
    r.arr_forfeited_usd / t.closed_won_arr_usd > 0.02 AS material_sales_impact
FROM rolled AS r
CROSS JOIN totals AS t
ORDER BY
    r.scenario,
    CASE WHEN r.channel = '(all channels)' THEN 1 ELSE 0 END,
    r.spend_removed_usd DESC;
