-- Question: how do we measure marketing when direct attribution is incomplete?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/06_effectiveness_when_attribution_is_incomplete.sql"
--
-- The coverage section shows how much Closed Won ARR each identifier can
-- see at all. The channel section then scores the same spend five ways.
-- ARR per dollar is comparable across methods because the spend column is
-- the channel's full invoice, not a re-allocated cost.
--
-- None of these is a causal increment. There is no holdout in the extract.
-- The even multi-touch row is the one to use for contribution, because it
-- is the only method that both survives the broken last-touch weights and
-- still assigns the leads that have no journey. Sales-sourced ARR with no
-- lead is reported in coverage and is not given to a channel.
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
method_credit AS (
    SELECT
        'even_multi_touch_with_source_fallback' AS method,
        campaign_id,
        arr_credit
    FROM credited
    UNION ALL
    SELECT
        'platform_source_campaign',
        l.source_campaign_id,
        w.arr_usd
    FROM won AS w
    JOIN lead AS l
        ON w.source_lead_id = l.lead_id
    WHERE l.source_campaign_id IS NOT NULL
    UNION ALL
    SELECT
        'rep_stamped_primary_campaign',
        primary_campaign_id,
        arr_usd
    FROM won
    WHERE primary_campaign_id IS NOT NULL
    UNION ALL
    SELECT
        'first_touch_flag_renormalized',
        f.campaign_id,
        w.arr_usd * f.attribution_weight_first / f.first_sum
    FROM won AS w
    JOIN touch_flags AS f
        ON w.source_lead_id = f.lead_id
    WHERE f.first_sum > 0
      AND f.attribution_weight_first <> 0
    UNION ALL
    SELECT
        'last_touch_flag_renormalized',
        f.campaign_id,
        w.arr_usd * f.attribution_weight_last / f.last_sum
    FROM won AS w
    JOIN touch_flags AS f
        ON w.source_lead_id = f.lead_id
    WHERE f.last_sum > 0
      AND f.attribution_weight_last <> 0
),
method_note AS (
    SELECT * FROM (VALUES
        (
            'even_multi_touch_with_source_fallback',
            'Equal credit across touches. No-touch leads fall back to the platform source campaign.'
        ),
        (
            'platform_source_campaign',
            'One campaign per converting lead: the platform source_campaign_id. Misses assists and every win with no lead.'
        ),
        (
            'rep_stamped_primary_campaign',
            'The campaign the rep typed on the opportunity. Blank on a large share of wins.'
        ),
        (
            'first_touch_flag_renormalized',
            'Platform first-touch flag, divided so the weights still sum to 1 after duplicate leads are merged.'
        ),
        (
            'last_touch_flag_renormalized',
            'Platform last-touch flag, repaired by dividing by the lead total. Leads whose flags sum to 0 stay uncredited.'
        )
    ) AS v(method, how_to_read)
),
won_arr AS (
    SELECT SUM(arr_usd) AS closed_won_arr_usd FROM won
),
coverage AS (
    SELECT 'won_arr' AS method, SUM(arr_usd) AS arr_usd FROM won
    UNION ALL
    SELECT 'won_arr_with_source_lead', SUM(arr_usd) FROM won WHERE source_lead_id IS NOT NULL
    UNION ALL
    SELECT 'won_arr_with_any_touchpoint', SUM(w.arr_usd)
    FROM won AS w
    JOIN touch_counts AS c ON w.source_lead_id = c.lead_id
    UNION ALL
    SELECT 'won_arr_with_rep_stamped_campaign', SUM(arr_usd)
    FROM won
    WHERE primary_campaign_id IS NOT NULL
    UNION ALL
    SELECT 'won_arr_credited_by_even_multi_touch', SUM(arr_credit) FROM credited
    UNION ALL
    SELECT 'won_arr_sales_sourced_no_lead', SUM(arr_usd)
    FROM won
    WHERE source_lead_id IS NULL
),
channel_spend AS (
    SELECT channel, SUM(spend_usd) AS spend_usd
    FROM campaign
    GROUP BY channel
),
by_method AS (
    SELECT
        mc.method,
        c.channel,
        SUM(mc.arr_credit) AS arr_usd
    FROM method_credit AS mc
    JOIN campaign AS c
        USING (campaign_id)
    GROUP BY mc.method, c.channel
)
SELECT
    'coverage' AS result_section,
    c.method,
    CAST(NULL AS VARCHAR) AS channel,
    ROUND(c.arr_usd, 2) AS arr_usd,
    ROUND(c.arr_usd / w.closed_won_arr_usd, 4) AS share_of_closed_won_arr,
    CAST(NULL AS DOUBLE) AS marketing_spend_usd,
    CAST(NULL AS DOUBLE) AS arr_per_spend_dollar,
    CASE c.method
        WHEN 'won_arr' THEN 'Denominator. Every Closed Won dollar, however it was sourced.'
        WHEN 'won_arr_with_source_lead' THEN 'Wins a marketing lead can explain. The rest are sales-sourced.'
        WHEN 'won_arr_with_any_touchpoint' THEN 'Wins whose lead has a journey. The gap versus the source-lead row is the missing touchpoint coverage.'
        WHEN 'won_arr_with_rep_stamped_campaign' THEN 'Wins the rep actually tagged with a campaign.'
        WHEN 'won_arr_credited_by_even_multi_touch' THEN 'Wins the working model can distribute. This is the covered portion.'
        WHEN 'won_arr_sales_sourced_no_lead' THEN 'Do not force this ARR onto a campaign. Report it beside marketing-credited ARR.'
    END AS how_to_read
FROM coverage AS c
CROSS JOIN won_arr AS w
UNION ALL
SELECT
    'channel' AS result_section,
    n.method,
    s.channel,
    ROUND(COALESCE(b.arr_usd, 0), 2) AS arr_usd,
    ROUND(COALESCE(b.arr_usd, 0) / w.closed_won_arr_usd, 4) AS share_of_closed_won_arr,
    ROUND(s.spend_usd, 2) AS marketing_spend_usd,
    ROUND(COALESCE(b.arr_usd, 0) / NULLIF(s.spend_usd, 0), 3) AS arr_per_spend_dollar,
    n.how_to_read
FROM channel_spend AS s
CROSS JOIN method_note AS n
LEFT JOIN by_method AS b
    ON b.channel = s.channel
   AND b.method = n.method
CROSS JOIN won_arr AS w
ORDER BY
    CASE result_section WHEN 'coverage' THEN 0 ELSE 1 END,
    CASE method
        WHEN 'won_arr' THEN 1
        WHEN 'won_arr_with_source_lead' THEN 2
        WHEN 'won_arr_with_any_touchpoint' THEN 3
        WHEN 'won_arr_with_rep_stamped_campaign' THEN 4
        WHEN 'won_arr_credited_by_even_multi_touch' THEN 5
        WHEN 'won_arr_sales_sourced_no_lead' THEN 6
        ELSE 10
    END,
    method,
    arr_per_spend_dollar DESC NULLS LAST,
    channel;
