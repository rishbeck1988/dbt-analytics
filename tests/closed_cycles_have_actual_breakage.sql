select
    payment_id,
    cycle_status,
    actual_breakage_hours
from {{ ref('fct_payments') }}
where cycle_status = 'closed'
  and actual_breakage_hours is null