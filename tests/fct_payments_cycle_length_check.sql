select
    payment_id,
    cycle_start,
    cycle_end,
    datediff(cycle_end, cycle_start) as actual_days
from {{ ref('fct_payments') }}
where datediff(cycle_end, cycle_start) != {{ var('cycle_length_days') }} - 1