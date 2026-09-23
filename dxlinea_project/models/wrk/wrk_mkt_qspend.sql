with source as (

    select * from {{ ref('wrk_mkt_campaign') }}

)

, base_model as (

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
        planned_spend_usd,
        actual_spend_local,
        actual_spend_usd,
        is_active
    from source
)

, agg_spend as (
    select 
        fiscal_quarter
        ,sum(planned_spend_usd) as planned_spend_usd
        ,sum(actual_spend_usd) as actual_spend_usd
    from base_model
    group by fiscal_quarter

)

, delta_spend as (

    select 
        fiscal_quarter
        ,planned_spend_usd
        ,actual_spend_usd
        ,planned_spend_usd - actual_spend_usd as delta_spend_usd
    from agg_spend
)

select * from delta_spend