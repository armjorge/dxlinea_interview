with source as (

    select * from {{ ref('stg_mkt_campaign') }}

),

stg_model as (

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
        actual_spend_local,
        is_active
    from source

)

, all_to_usd as (

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
    from stg_model

)

select * from all_to_usd