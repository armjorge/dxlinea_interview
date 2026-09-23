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
        to_date(created_date) as created_date,
        to_date(close_date) as close_date,
        stage_name,
        cast(is_closed as boolean) as is_closed,
        cast(is_won as boolean) as is_won,
        cast(term_months as integer) as term_months,
        cast(amount_usd as numeric(18,2)) as amount_usd,
        cast(arr_usd as numeric(18,2)) as arr_usd,
        sales_rep

    from source

)

select * from renamed

