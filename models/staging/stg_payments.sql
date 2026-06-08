select
    payment_id,
    student_id,
    payment_ts,
    date(payment_ts) as payment_date,
    hours as hours_purchased,
    price_per_hour_usd,
    hours * price_per_hour_usd as total_plan_value_usd
from {{ ref('raw_payments') }}
where payment_id is not null
  and student_id is not null
  and payment_ts is not null
  and price_per_hour_usd > 0