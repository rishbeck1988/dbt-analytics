-- commission + breakage should never exceed total plan value
-- Preply earns from two sources but total cannot exceed what student paid
select
    payment_id,
    total_plan_value_usd,
    commission_usd,
    breakage_usd,
    round(commission_usd + breakage_usd, 2)     as total_revenue,
    total_plan_value_usd                         as max_possible
from {{ ref('fct_payments') }}
where round(commission_usd + breakage_usd, 2)
    > total_plan_value_usd + 0.01