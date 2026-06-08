-- cycle_end must always be after cycle_start
select
    payment_id,
    cycle_start,
    cycle_end
from {{ ref('int_payment_cycles') }}
where cycle_end < cycle_start