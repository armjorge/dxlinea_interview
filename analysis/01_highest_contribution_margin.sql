-- Question: which products, locations, and campaigns generate the highest
-- contribution margins?
--
-- Run from the repository root:
--   duckdb -c ".read analysis/01_highest_contribution_margin.sql"
--
-- Contribution margin here is one-year ARR minus the marketing spend
-- allocated to that row. The workbook has no cost of goods, gross-margin
-- rate, or churn, so this is the contribution after marketing only. It is
-- a ceiling on economic contribution, not a GAAP gross margin.
--
-- Products and locations keep every Closed Won dollar, including
-- sales-sourced deals. Spend is spread in proportion to marketing-credited
-- ARR. Invoiced spend that never touches a Closed Won deal stays in two
-- unallocated rows (mature miss vs immature, not yet closed). It is not
-- dumped onto a product.
--
-- Campaign rows are different on purpose: a campaign can only claim the ARR
-- its touches (or the source-campaign fallback) earned. is_mature is false
-- when the campaign ended after 31 March 2026. Those rows can look terrible
-- because the deal has not had time to close. Read that flag before calling
-- a negative campaign waste.
--
-- Location is the opportunity region. In this extract each region has one
-- country (NAM = United States, EMEA = Germany, APJ = Australia,
-- LATAM = Mexico). Account billing region disagrees with the opportunity on
-- about half of won deals, while the opportunity region matches the campaign
-- region on 87% of deals that have one, so the opportunity is the location.
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
spend_alloc AS (
    SELECT
        cr.product_line,
        cr.region,
        cr.campaign_id,
        cr.arr_credit,
        c.spend_usd * cr.arr_credit / NULLIF(cc.arr_credit, 0) AS spend_alloc
    FROM credited AS cr
    JOIN campaign AS c
        USING (campaign_id)
    JOIN campaign_credit AS cc
        USING (campaign_id)
    WHERE cc.arr_credit > 0
      AND c.spend_usd IS NOT NULL
),
product_arr AS (
    SELECT product_line, SUM(arr_usd) AS arr_usd
    FROM won
    GROUP BY product_line
),
product_spend AS (
    SELECT product_line, SUM(spend_alloc) AS spend_usd
    FROM spend_alloc
    GROUP BY product_line
),
product_rows AS (
    SELECT
        'product' AS dimension,
        a.product_line AS name,
        CAST(NULL AS VARCHAR) AS channel,
        CAST(NULL AS VARCHAR) AS program_type,
        'all_closed_won_arr' AS arr_basis,
        a.arr_usd,
        COALESCE(s.spend_usd, 0) AS marketing_spend_usd,
        CAST(NULL AS BOOLEAN) AS is_mature
    FROM product_arr AS a
    LEFT JOIN product_spend AS s
        USING (product_line)
),
location_arr AS (
    SELECT region, SUM(arr_usd) AS arr_usd
    FROM won
    GROUP BY region
),
location_spend AS (
    SELECT region, SUM(spend_alloc) AS spend_usd
    FROM spend_alloc
    GROUP BY region
),
location_rows AS (
    SELECT
        'location' AS dimension,
        a.region || ' - ' || CASE a.region
            WHEN 'NAM' THEN 'United States'
            WHEN 'EMEA' THEN 'Germany'
            WHEN 'APJ' THEN 'Australia'
            WHEN 'LATAM' THEN 'Mexico'
            ELSE 'unmapped country'
        END AS name,
        CAST(NULL AS VARCHAR) AS channel,
        CAST(NULL AS VARCHAR) AS program_type,
        'all_closed_won_arr' AS arr_basis,
        a.arr_usd,
        COALESCE(s.spend_usd, 0) AS marketing_spend_usd,
        CAST(NULL AS BOOLEAN) AS is_mature
    FROM location_arr AS a
    LEFT JOIN location_spend AS s
        USING (region)
),
campaign_rows AS (
    SELECT
        'campaign' AS dimension,
        campaign_name AS name,
        channel,
        program_type,
        'marketing_credited_arr' AS arr_basis,
        arr_credit AS arr_usd,
        spend_usd AS marketing_spend_usd,
        is_mature
    FROM campaign_econ
),
unallocated AS (
    -- Zero-credit spend only. Campaigns that earned any ARR have their whole
    -- invoice allocated above. Immature zero-credit spend has not had a
    -- chance to close; mature zero-credit spend is the part that missed.
    SELECT
        'unallocated_spend' AS dimension,
        CASE
            WHEN is_mature THEN 'Mature invoiced spend with no Closed Won credit'
            ELSE 'Immature invoiced spend with no Closed Won credit yet'
        END AS name,
        CAST(NULL AS VARCHAR) AS channel,
        CAST(NULL AS VARCHAR) AS program_type,
        'none' AS arr_basis,
        0.0 AS arr_usd,
        SUM(spend_usd) AS marketing_spend_usd,
        is_mature
    FROM campaign_econ
    WHERE spend_usd IS NOT NULL
      AND arr_credit = 0
    GROUP BY is_mature
),
scored AS (
    SELECT
        dimension,
        name,
        channel,
        program_type,
        arr_basis,
        arr_usd,
        marketing_spend_usd,
        is_mature,
        arr_usd - marketing_spend_usd AS contribution_margin_usd,
        arr_usd / NULLIF(marketing_spend_usd, 0) AS roi
    FROM (
        SELECT * FROM product_rows
        UNION ALL
        SELECT * FROM location_rows
        UNION ALL
        SELECT * FROM campaign_rows
        UNION ALL
        SELECT * FROM unallocated
    ) AS u
    WHERE marketing_spend_usd IS NOT NULL OR arr_usd IS NOT NULL
)
SELECT
    dimension,
    CASE
        WHEN dimension = 'unallocated_spend' THEN NULL
        ELSE ROW_NUMBER() OVER (
            PARTITION BY dimension
            ORDER BY contribution_margin_usd DESC NULLS LAST, name
        )
    END AS rank_by_contribution_margin,
    name,
    channel,
    program_type,
    is_mature,
    arr_basis,
    ROUND(arr_usd, 2) AS arr_usd,
    ROUND(marketing_spend_usd, 2) AS marketing_spend_usd,
    ROUND(contribution_margin_usd, 2) AS contribution_margin_usd,
    ROUND(roi, 3) AS roi
FROM scored
ORDER BY
    CASE dimension
        WHEN 'product' THEN 1
        WHEN 'location' THEN 2
        WHEN 'campaign' THEN 3
        ELSE 4
    END,
    rank_by_contribution_margin NULLS LAST;
