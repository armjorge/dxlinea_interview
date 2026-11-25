-- Question: what is the incremental return on additional advertising spend?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/07_incremental_return_on_advertising.sql"
--
-- Inside each channel, mature campaigns are split into three spend bands
-- (low, middle, high). Average ROI of a band is not the return on the next
-- dollar. The marginal return is the change in average credited ARR divided
-- by the change in average spend as you step from band 1 to 2, then 2 to 3.
--
-- A marginal return above 1 means the more expensive band still adds more
-- year-1 ARR than it adds spend. Below 1, the extra budget raises sales
-- and lowers contribution. Band 1 has no marginal return; it is the base.
--
-- highest_observed_increment marks the best band-3 step whose average spend
-- is at least 25% above the middle band. A channel whose campaigns are all
-- about the same size can post a wild marginal ROI on a tiny denominator;
-- that step is left unmarked.
--
-- This is a comparison of campaigns that already ran, not a controlled
-- experiment. Channels with fewer than six mature campaigns are flagged
-- so a three-campaign split is not treated as a curve.
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
mature_positive AS (
    SELECT
        channel,
        campaign_id,
        spend_usd,
        arr_credit,
        NTILE(3) OVER (PARTITION BY channel ORDER BY spend_usd, campaign_id) AS spend_band
    FROM campaign_econ
    WHERE is_mature
      AND spend_usd IS NOT NULL
      AND spend_usd > 0
),
channel_size AS (
    SELECT channel, COUNT(*) AS mature_campaigns
    FROM mature_positive
    GROUP BY channel
),
bands AS (
    SELECT
        p.channel,
        p.spend_band,
        COUNT(*) AS campaigns,
        SUM(p.spend_usd) AS spend_usd,
        SUM(p.arr_credit) AS arr_credit,
        AVG(p.spend_usd) AS avg_spend_usd,
        AVG(p.arr_credit) AS avg_arr_usd,
        s.mature_campaigns >= 6 AS enough_campaigns_for_a_curve
    FROM mature_positive AS p
    JOIN channel_size AS s
        USING (channel)
    GROUP BY p.channel, p.spend_band, s.mature_campaigns
),
stepped AS (
    SELECT
        h.channel,
        h.spend_band,
        h.campaigns,
        h.spend_usd,
        h.arr_credit,
        h.avg_spend_usd,
        h.avg_arr_usd,
        l.avg_spend_usd AS lower_avg_spend_usd,
        h.enough_campaigns_for_a_curve,
        CASE
            WHEN l.channel IS NULL THEN NULL
            WHEN h.avg_spend_usd <= l.avg_spend_usd THEN NULL
            ELSE (h.avg_arr_usd - l.avg_arr_usd) / (h.avg_spend_usd - l.avg_spend_usd)
        END AS marginal_roi_vs_lower_band
    FROM bands AS h
    LEFT JOIN bands AS l
        ON h.channel = l.channel
       AND h.spend_band = l.spend_band + 1
)
SELECT
    channel,
    spend_band,
    campaigns,
    enough_campaigns_for_a_curve,
    ROUND(spend_usd, 2) AS spend_usd,
    ROUND(avg_spend_usd, 2) AS avg_spend_usd,
    ROUND(arr_credit, 2) AS credited_arr_usd,
    ROUND(arr_credit / NULLIF(spend_usd, 0), 3) AS band_roi,
    ROUND(marginal_roi_vs_lower_band, 3) AS marginal_roi_vs_lower_band,
    CASE
        WHEN marginal_roi_vs_lower_band IS NULL THEN NULL
        ELSE marginal_roi_vs_lower_band > 1
    END AS additional_spend_still_profitable,
    spend_band = 3
        AND enough_campaigns_for_a_curve
        AND marginal_roi_vs_lower_band IS NOT NULL
        AND avg_spend_usd >= 1.25 * lower_avg_spend_usd
        AND marginal_roi_vs_lower_band = MAX(marginal_roi_vs_lower_band) FILTER (
            WHERE spend_band = 3
              AND enough_campaigns_for_a_curve
              AND marginal_roi_vs_lower_band IS NOT NULL
              AND avg_spend_usd >= 1.25 * lower_avg_spend_usd
        ) OVER () AS highest_observed_increment
FROM stepped
ORDER BY channel, spend_band;
