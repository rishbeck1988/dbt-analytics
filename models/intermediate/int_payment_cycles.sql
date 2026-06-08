with payments as (
    select * from {{ ref('stg_payments') }}
),

students as (
    select * from {{ ref('stg_students') }}
),

first_payments as (
    select
        student_id,
        min(payment_date)                       as first_payment_date
    from payments
    group by student_id
),

cycles as (
    select
        p.payment_id,
        p.student_id,
        p.payment_ts,
        p.payment_date                          as cycle_start,

        -- cycle_end = last active day (inclusive)
        -- payment_date + 27 for a 28-day cycle
        -- no overlap with next cycle which starts on payment_date + 28
        cast(
            dateadd(
                day,
                {{ var('cycle_length_days') }} - 1,
                p.payment_date
            )
        as date)                                as cycle_end,

        p.hours_purchased,
        p.price_per_hour_usd,
        p.total_plan_value_usd,

        -- closed when cycle_end has passed as_of_date
        case
            when cast(
                dateadd(
                    day,
                    {{ var('cycle_length_days') }} - 1,
                    p.payment_date
                )
            as date) <= cast('{{ var("as_of_date") }}' as date)
            then 'closed'
            else 'open'
        end                                     as cycle_status,

        -- days elapsed capped at cycle_length_days - 1 (max = day 27)
        least(
            datediff(
                cast('{{ var("as_of_date") }}' as date),
                p.payment_date
            ),
            {{ var('cycle_length_days') }} - 1
        )                                       as days_elapsed,

        -- days remaining floored at 0
        greatest(
            {{ var('cycle_length_days') }} - 1 - datediff(
                cast('{{ var("as_of_date") }}' as date),
                p.payment_date
            ),
            0
        )                                       as days_remaining,

        case
            when fp.first_payment_date = p.payment_date
            then 'new'
            else 'returning'
        end                                     as student_type,

        row_number() over (
            partition by p.student_id
            order by p.payment_date
        )                                       as cycle_number

    from payments p
    left join first_payments fp
        on p.student_id = fp.student_id
)

select
    c.payment_id,
    c.student_id,
    c.payment_ts,
    c.cycle_start,
    c.cycle_end,
    c.hours_purchased,
    c.price_per_hour_usd,
    c.total_plan_value_usd,
    c.cycle_status,
    c.days_elapsed,
    c.days_remaining,
    c.student_type,
    c.cycle_number,
    s.country_code,
    s.persona,
    s.acquisition_channel,
    s.first_subject,
    s.join_date,
    trunc(s.join_date, 'MM')                    as join_cohort,
    trunc(c.cycle_start, 'MM')                  as payment_cohort

from cycles c
left join students s
    on c.student_id = s.student_id