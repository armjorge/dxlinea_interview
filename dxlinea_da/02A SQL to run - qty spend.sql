-- Spend, in a single currency

with all_to_usd as (

    select
        campaign_id,
        campaign_name,
        channel,
        sub_channel,
        program_type,
        region,
        target_segment,
        fiscal_quarter,
        start_date,
        end_date,
        currency_code,
        fx_rate_to_usd,
        planned_spend_local,
        fx_rate_to_usd * planned_spend_local as planned_spend_usd,
        actual_spend_local,
        fx_rate_to_usd * actual_spend_local as actual_spend_usd,
        is_active
    from DXLINEA_INTERVIEW.RAW_DXLINEA.stg_mkt_campaign

) 
-- materialized as wrk_mkt_campaign to further use. 
SELECT * FROM all_to_usd LIMIT 50; 


-- available quarters
SELECT DISTINCT fiscal_quarter
FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_MKT_CAMPAIGN order by 1;


--  High level quantity planned vs quantity spend  in dollars
SELECT 
    fiscal_quarter
    ,ROUND(SUM(planned_spend_usd),2)  as total_planned_spend_usd
    ,ROUND(SUM(actual_spend_usd),2)  as total_actual_spend_usd
    ,ROUND(total_planned_spend_usd - total_actual_spend_usd, 2) AS delta_spend
    ,ROUND((delta_spend/total_planned_spend_usd) * 100, 2) AS percentage_spend
FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_MKT_CAMPAIGN
WHERE fiscal_quarter = '2026Q3'
GROUP BY fiscal_quarter;

-- We've spend 1,173,070.22 USD in the present 2026Q3 

SELECT 
    fiscal_quarter
    ,sub_channel
    ,SUM(planned_spend_usd) as total_planned_spend_usd
    ,SUM(actual_spend_usd) as total_actual_spend_usd
    ,ROUND(total_planned_spend_usd - total_actual_spend_usd, 2) AS delta_spend
    ,ROUND((delta_spend/total_planned_spend_usd) * 100, 2) AS percentage_spend
FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_MKT_CAMPAIGN
WHERE fiscal_quarter = '2026Q3'
GROUP BY 
    fiscal_quarter
    ,sub_channel 
ORDER BY 
    percentage_spend
-- The quantity was spend between 21 providers, only one pass a limit higher than it's 10%, there are other three passing their limits by quantities close to exchange rate variation, while 17 keeps in it's limits. 
;




-- Additional 
SELECT 
    fiscal_quarter
    ,channel
    ,sub_channel
    ,SUM(planned_spend_usd) as total_planned_spend_usd
    ,SUM(actual_spend_usd) as total_actual_spend_usd
    ,ROUND(total_planned_spend_usd - total_actual_spend_usd, 2) AS delta_spend
    ,ROUND((delta_spend/total_planned_spend_usd) * 100, 2) AS percentage_spend
FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_MKT_CAMPAIGN
WHERE fiscal_quarter = '2026Q3'
GROUP BY 
    fiscal_quarter
    ,channel
    ,sub_channel 
    
ORDER BY 
    channel
    ,sub_channel
;



SELECT * 
FROM DXLINEA_INTERVIEW.WRK_DXLINEA.WRK_MKT_CAMPAIGN LIMIT 50; 

-- Leads, MQLs and disqualification rate

-- Opportunities created and pipeline generated

-- Closed-won revenue

-- The efficiency ratios you think VP should be managing to
