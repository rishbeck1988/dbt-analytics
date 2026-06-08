-- breakage_hours can never exceed hours_purchased
-- applies to both actual (closed) and estimated (open) cycles
select
    payment_id,
    cycle_status,
    is_estimate,
    hours_purchased,
    breakage_hours,
    breakage_usd
from {{ ref('fct_payments') }}
where breakage_hours > hours_purchased