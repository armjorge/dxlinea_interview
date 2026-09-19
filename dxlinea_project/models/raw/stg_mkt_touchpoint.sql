with source as (

    select * from {{ source('raw_dxlinea', 'MKT_TOUCHPOINT') }}

),

renamed as (

    select
        touchpoint_id,
        lead_id,
        campaign_id,
        touch_date,
        touch_seq,
        touch_type,
        attribution_weight_first,
        attribution_weight_last

    from source

)

select * from renamed
