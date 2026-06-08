 select
    payment_id,
    hours_purchased,
    hours_booked_so_far,
    actual_breakage_hours,
    round(hours_booked_so_far + actual_breakage_hours, 2) as total_accounted
from {{ ref('fct_payments') }}
where cycle_status = 'closed'
  and hours_booked_so_far <= hours_purchased    -- exclude overbooking cases
  and round(hours_booked_so_far + actual_breakage_hours, 2)
      != hours_purchased