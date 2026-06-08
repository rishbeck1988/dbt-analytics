-- fct_payments should have same row count as stg_payments
-- any difference means payments were lost in transformation
select
    stg.payment_count       as stg_count,
    fct.payment_count       as fct_count,
    stg.payment_count - fct.payment_count as difference
from (
    select count(*) as payment_count
    from {{ ref('stg_payments') }}
) stg
cross join (
    select count(*) as payment_count
    from {{ ref('fct_payments') }}
) fct
where stg.payment_count != fct.payment_count