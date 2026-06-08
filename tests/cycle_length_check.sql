-- cycle_end must be exactly cycle_length_days - 1 after cycle_start
-- for a 28-day cycle: cycle_end = cycle_start + 27 days
select
    payment_id,
    cycle_start,
    cycle_end,
    datediff(cycle_end, cycle_start)        as actual_days,
    {{ var('cycle_length_days') }} - 1      as expected_days
from {{ ref('int_payment_cycles') }}
where datediff(cycle_end, cycle_start) != {{ var('cycle_length_days') }} - 1