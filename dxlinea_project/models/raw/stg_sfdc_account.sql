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
        is_customer,
        first_closed_won_date,
        account_owner

    from source

)

select * from renamed


