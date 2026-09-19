with source as (

    select * from {{ source('raw_dxlinea', 'MKT_LEAD') }}

),

renamed as (

    select
        lead_id,
        account_id,
        email,
        created_date,
        source_campaign_id,
        lead_status,
        mql_date,
        is_disqualified,
        disqualify_reason,
        country,
        region,
        industry,
        sales_segment,
        job_level

    from source

)

select * from renamed

