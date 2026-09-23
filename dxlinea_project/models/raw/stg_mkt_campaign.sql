with source as (

    select * from {{ source('raw_dxlinea', 'MKT_CAMPAIGN') }}

),

renamed as (

    select
        campaign_id,
        campaign_name,
        channel,
        sub_channel,
        program_type,
        region,
        target_segment,
        fiscal_quarter,
        to_date(start_date) as start_date,
        to_date(end_date) as end_date,
        currency_code,
        cast(fx_rate_to_usd as numeric(18,2)) as fx_rate_to_usd,
        cast(planned_spend_local as numeric(18,2)) as planned_spend_local,
        cast(actual_spend_local as numeric(18,2)) as actual_spend_local,
        cast(is_active as boolean) as is_active


    from source

)

select * from renamed

