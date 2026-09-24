WITH opportunities_analysis as ( 
    SELECT  
        EXTRACT(YEAR FROM OP_A.created_date) || 'Q' || EXTRACT(QUARTER FROM OP_A.created_date) AS CREATION_QUARTER
        ,EXTRACT(YEAR FROM OP_A.close_date) || 'Q' || EXTRACT(QUARTER FROM OP_A.close_date) AS CLOSE_QUARTER
        ,COALESCE(EXTRACT(YEAR FROM MK_L.CREATED_DATE) || 'Q' || EXTRACT(QUARTER FROM MK_L.CREATED_DATE)
         , CREATION_QUARTER ) AS LEAD_QUARTER
        ,CREATION_QUARTER = CLOSE_QUARTER AS HAPPEND_IN_SAME_QUARTER
        ,*
    FROM {{ ref('stg_sfdc_opportunity') }} OP_A
    LEFT JOIN {{ ref('stg_mkt_lead') }} MK_L
        ON OP_A.SOURCE_LEAD_ID = MK_L.LEAD_ID
    
    -- WHERE  HAPPEND_IN_SAME_QUARTER = TRUE -- Only 282 records from 2188 where created and closed in the same quarter. 
    -- After joining, the same 2188 rows remains. 488 records don't links to a lead, leaving the creation_quarter as the default for them 
) 


, OPPORTUNITIES_PER_Q AS ( 

    SELECT 
        CREATION_QUARTER
        ,COUNT(OPPORTUNITY_ID) AS QUARTER_OPPORTUNITY
    FROM opportunities_analysis
    GROUP BY 1
)
-- SELECT * FROM  OPPORTUNITIES_PER_Q ; 

SELECT
    OP_A.CREATION_QUARTER
    ,OP_A.STAGE_NAME
    ,SUM(OP_A.AMOUNT_USD) AS TOTAL_AMOUNT
    ,SUM(OP_A.ARR_USD) AS YEAR_AMOUNT
    ,COUNT(OP_A.OPPORTUNITY_ID) AS Q_STAGE_OPPORTUNITIES
    ,MAX(OP_Q.QUARTER_OPPORTUNITY) AS TOTAL_OPPORTUNITIES
    ,ROUND(100 * Q_STAGE_OPPORTUNITIES/ TOTAL_OPPORTUNITIES,2 )  AS OPPORTUNITIES_PCT
FROM opportunities_analysis OP_A
LEFT JOIN OPPORTUNITIES_PER_Q OP_Q
ON OP_A.CREATION_QUARTER = OP_Q.CREATION_QUARTER
GROUP BY 1, 2
ORDER BY 1, 2
--materialized as wrk_opportunities_analysis


