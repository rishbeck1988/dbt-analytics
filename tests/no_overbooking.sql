{{ config(severity='warn') }}
select
    payment_id,
    hours_purchased,
    hours_booked_so_far
from {{ ref('fct_payments') }}
where hours_booked_so_far > hours_purchased