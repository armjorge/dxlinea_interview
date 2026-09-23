with source as (

    select * from {{ source('raw_dxlinea', 'MKT_TOUCHPOINT') }}

),

renamed as (

    select
        touchpoint_id,
        lead_id,
        campaign_id,
        to_date(touch_date) as touch_date,
        cast(touch_seq as integer) as touch_seq,
        touch_type,
        cast(attribution_weight_first as numeric(2,1)) as attribution_weight_first,
        cast(attribution_weight_last as numeric(2,1)) as attribution_weight_last


    from source

)

select * from renamed
