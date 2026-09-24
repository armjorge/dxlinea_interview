WITH LEADS_PER_QUARTER AS ( 
    SELECT 
        EXTRACT(YEAR FROM created_date) || 'Q' || EXTRACT(QUARTER FROM created_date) AS lead_quarter
        ,COUNT (DISTINCT LEAD_ID) AS LEADS_QTY
    FROM {{ ref('stg_mkt_lead') }}
    GROUP BY 1
    )

, LEAD_STATUS_PER_QUARTER AS ( 
    SELECT 
        EXTRACT(YEAR FROM created_date) || 'Q' || EXTRACT(QUARTER FROM created_date) AS lead_quarter
        ,LEAD_STATUS
        ,COUNT (DISTINCT LEAD_ID) AS LEADS_QTY
    FROM {{ ref('stg_mkt_lead') }}
    GROUP BY 1, 2

    )

, LEADS_GROWTH AS ( 
    SELECT 
        LSPT_Q.LEAD_QUARTER
        ,LSPT_Q.LEAD_STATUS
        ,LSPT_Q.LEADS_QTY
        ,LDS_PQ.LEADS_QTY AS QUARTER_LEADS
        ,ROUND((100* LSPT_Q.LEADS_QTY / LDS_PQ.LEADS_QTY ), 2)  AS STATUS_PRC
    FROM LEAD_STATUS_PER_QUARTER LSPT_Q
    LEFT JOIN LEADS_PER_QUARTER LDS_PQ
    ON LSPT_Q.LEAD_QUARTER = LDS_PQ.LEAD_QUARTER
    )


,quarter_budget as ( 
    select
        fiscal_quarter,
        sum(planned_spend_usd) as planned_spend_usd,
        sum(actual_spend_usd) as actual_spend_usd,
    from {{ ref('wrk_mkt_campaign') }}
    group by fiscal_quarter

)

, LEADS_GROWTH_AND_QUARTER_COST AS ( 
    SELECT 
        LE_GR.* 
        ,Q_BDGT.planned_spend_usd
        ,Q_BDGT.actual_spend_usd
        ,round(Q_BDGT.actual_spend_usd / QUARTER_LEADS, 2) as LEAD_COST
    FROM LEADS_GROWTH LE_GR
    LEFT JOIN QUARTER_BUDGET Q_BDGT
    ON Q_BDGT.fiscal_quarter = LE_GR.LEAD_QUARTER

)


select * from LEADS_GROWTH_AND_QUARTER_COST