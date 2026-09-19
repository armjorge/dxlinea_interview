with source as (

    select * from {{ source('raw_dxlinea', 'SFDC_OPPORTUNITY') }}

),

renamed as (

    select
        opportunity_id,
        account_id,
        source_lead_id,
        primary_campaign_id,
        opportunity_type,
        product_line,
        sales_segment,
        region,
        created_date,
        close_date,
        stage_name,
        is_closed,
        is_won,
        term_months,
        amount_usd,
        arr_usd,
        sales_rep

    from source

)

select * from renamed

