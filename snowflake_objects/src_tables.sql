
USE DATABASE dxlinea_interview;
USE SCHEMA raw_dxlinea;
CREATE OR REPLACE TABLE mkt_campaign AS
SELECT
    $1:"campaign_id"::VARCHAR AS campaign_id,
    $1:"campaign_name"::VARCHAR AS campaign_name,
    $1:"channel"::VARCHAR AS channel,
    $1:"sub_channel"::VARCHAR AS sub_channel,
    $1:"program_type"::VARCHAR AS program_type,
    $1:"region"::VARCHAR AS region,
    $1:"target_segment"::VARCHAR AS target_segment,
    $1:"fiscal_quarter"::VARCHAR AS fiscal_quarter,
    $1:"start_date"::VARCHAR AS start_date,
    $1:"end_date"::VARCHAR AS end_date,
    $1:"currency_code"::VARCHAR AS currency_code,
    $1:"fx_rate_to_usd"::VARCHAR AS fx_rate_to_usd,
    $1:"planned_spend_local"::VARCHAR AS planned_spend_local,
    $1:"actual_spend_local"::VARCHAR AS actual_spend_local,
    $1:"is_active"::VARCHAR AS is_active
FROM @DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE/mkt_campaign.parquet
    (FILE_FORMAT => 'DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF');

CREATE OR REPLACE TABLE mkt_lead AS
SELECT
    $1:"lead_id"::VARCHAR AS lead_id,
    $1:"account_id"::VARCHAR AS account_id,
    $1:"email"::VARCHAR AS email,
    $1:"created_date"::VARCHAR AS created_date,
    $1:"source_campaign_id"::VARCHAR AS source_campaign_id,
    $1:"lead_status"::VARCHAR AS lead_status,
    $1:"mql_date"::VARCHAR AS mql_date,
    $1:"is_disqualified"::VARCHAR AS is_disqualified,
    $1:"disqualify_reason"::VARCHAR AS disqualify_reason,
    $1:"country"::VARCHAR AS country,
    $1:"region"::VARCHAR AS region,
    $1:"industry"::VARCHAR AS industry,
    $1:"sales_segment"::VARCHAR AS sales_segment,
    $1:"job_level"::VARCHAR AS job_level
FROM @DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE/mkt_lead.parquet
    (FILE_FORMAT => 'DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF');

CREATE OR REPLACE TABLE mkt_touchpoint AS
SELECT
    $1:"touchpoint_id"::VARCHAR AS touchpoint_id,
    $1:"lead_id"::VARCHAR AS lead_id,
    $1:"campaign_id"::VARCHAR AS campaign_id,
    $1:"touch_date"::VARCHAR AS touch_date,
    $1:"touch_seq"::VARCHAR AS touch_seq,
    $1:"touch_type"::VARCHAR AS touch_type,
    $1:"attribution_weight_first"::VARCHAR AS attribution_weight_first,
    $1:"attribution_weight_last"::VARCHAR AS attribution_weight_last
FROM @DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE/mkt_touchpoint.parquet
    (FILE_FORMAT => 'DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF');

CREATE OR REPLACE TABLE sfdc_opportunity AS
SELECT
    $1:"opportunity_id"::VARCHAR AS opportunity_id,
    $1:"account_id"::VARCHAR AS account_id,
    $1:"source_lead_id"::VARCHAR AS source_lead_id,
    $1:"primary_campaign_id"::VARCHAR AS primary_campaign_id,
    $1:"opportunity_type"::VARCHAR AS opportunity_type,
    $1:"product_line"::VARCHAR AS product_line,
    $1:"sales_segment"::VARCHAR AS sales_segment,
    $1:"region"::VARCHAR AS region,
    $1:"created_date"::VARCHAR AS created_date,
    $1:"close_date"::VARCHAR AS close_date,
    $1:"stage_name"::VARCHAR AS stage_name,
    $1:"is_closed"::VARCHAR AS is_closed,
    $1:"is_won"::VARCHAR AS is_won,
    $1:"term_months"::VARCHAR AS term_months,
    $1:"amount_usd"::VARCHAR AS amount_usd,
    $1:"arr_usd"::VARCHAR AS arr_usd,
    $1:"sales_rep"::VARCHAR AS sales_rep
FROM @DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE/sfdc_opportunity.parquet
    (FILE_FORMAT => 'DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF');

CREATE OR REPLACE TABLE sfdc_account AS
SELECT
    $1:"account_id"::VARCHAR AS account_id,
    $1:"account_name"::VARCHAR AS account_name,
    $1:"region"::VARCHAR AS region,
    $1:"country"::VARCHAR AS country,
    $1:"industry"::VARCHAR AS industry,
    $1:"sales_segment"::VARCHAR AS sales_segment,
    $1:"employee_band"::VARCHAR AS employee_band,
    $1:"is_customer"::VARCHAR AS is_customer,
    $1:"first_closed_won_date"::VARCHAR AS first_closed_won_date,
    $1:"account_owner"::VARCHAR AS account_owner
FROM @DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE/sfdc_account.parquet
    (FILE_FORMAT => 'DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF');