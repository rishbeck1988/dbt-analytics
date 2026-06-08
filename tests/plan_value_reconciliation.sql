-- total plan value should match between stg and fct
-- any difference means revenue is being lost or inflated
select
    round(stg.total_value, 2)   as stg_total,
    round(fct.total_value, 2)   as fct_total
from (
    select sum(hours_purchased * price_per_hour_usd) as total_value
    from {{ ref('stg_payments') }}
) stg
cross join (
    select sum(total_plan_value_usd) as total_value
    from {{ ref('fct_payments') }}
) fct
where round(stg.total_value, 2) != round(fct.total_value, 2)