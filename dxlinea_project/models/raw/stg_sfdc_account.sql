with source as (

    select * from {{ source('raw_dxlinea', 'SFDC_ACCOUNT') }}

),

renamed as (

    select
        account_id,
        account_name,
        region,
        country,
        industry,
        sales_segment,
        employee_band,
        cast(is_customer as boolean) as is_customer,
        to_date(first_closed_won_date) as first_closed_won_date,
        account_owner

    from source

)

select * from renamed


