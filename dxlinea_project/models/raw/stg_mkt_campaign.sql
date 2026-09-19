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
        start_date,
        end_date,
        currency_code,
        fx_rate_to_usd,
        planned_spend_local,
        actual_spend_local,
        is_active

    from source

)

select * from renamed

