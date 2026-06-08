-- TODO: convert to incremental merge with md5 row hash strategy
-- Assess need of converting into into SCD Type-2 as well
with students as (
    select * from {{ ref('stg_students') }}
),

first_payments as (
    select
        student_id,
        min(payment_date)                       as first_payment_date,
        count(*)                                as total_payments
    from {{ ref('stg_payments') }}
    group by student_id
)

select
    s.student_id,
    s.join_ts,
    s.join_date,
    s.country_code,
    s.acquisition_channel,
    s.persona,
    s.first_subject,
    -- cohorts
    trunc(s.join_date, 'MM') as join_cohort,
    trunc(fp.first_payment_date, 'MM') as first_payment_cohort,
    -- first payment
    fp.first_payment_date,
    fp.total_payments,
    -- days between joining and first payment
    datediff(
        fp.first_payment_date,
        s.join_date
    ) as days_to_first_payment,

    -- student lifecycle stage
    case
        when fp.first_payment_date is null
        then 'never_paid'
        when fp.total_payments = 1
        then 'single_cycle'
        when fp.total_payments <= 3
        then 'early_lifecycle'
        else 'established'
    end                                         as lifecycle_stage

from students s
left join first_payments fp
    on s.student_id = fp.student_id