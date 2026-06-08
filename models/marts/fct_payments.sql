{{
    config(
        materialized='incremental',
        unique_key='payment_id',
        incremental_strategy='merge',
        merge_update_columns=[
            'cycle_status',
            'days_elapsed',
            'days_remaining',
            'hours_booked_so_far',
            'hours_remaining',
            'lessons_count',
            'last_booking_date',
            'daily_burn_rate',
            'is_fully_booked',
            'estimation_method',
            'actual_breakage_hours',
            'estimated_breakage_hours',
            'breakage_hours',
            'actual_breakage_usd',
            'estimated_breakage_usd',
            'breakage_usd',
            'is_estimate',
            'commission_usd',
            'total_revenue_usd',
            'updated_at'
        ]
    )
}}

with cycles as (
    select * from {{ ref('int_payment_cycles') }}
),

students as (
    select * from {{ ref('dim_students') }}
),

-- lesson consumption as of as_of_date
-- one row per payment, today's totals
lessons_mapped as (
    select
        c.payment_id,
        coalesce(sum(l.hours_booked), 0)        as hours_booked_so_far,
        count(l.lesson_id)                      as lessons_count,
        max(l.booking_date)                     as last_booking_date
    from cycles c
    left join {{ ref('stg_lessons') }} l
        on  l.student_id   = c.student_id
        and l.booking_date >= c.cycle_start
        and l.booking_date <=  c.cycle_end
    group by c.payment_id
),

-- historical rates — explicit CTE names passed to macro
{{ historical_rates_cte('cycles', 'lessons_mapped') }},

joined as (
    select
        c.payment_id,
        c.student_id,
        c.cycle_start,
        c.cycle_end,
        c.cycle_status,
        c.days_elapsed,
        c.days_remaining,
        c.hours_purchased,
        c.price_per_hour_usd,
        c.total_plan_value_usd,
        c.student_type,
        c.cycle_number,
        c.country_code,
        c.persona,
        c.acquisition_channel,
        c.first_subject,
        c.join_cohort,
        c.payment_cohort,
        c.join_date,

        -- student dims baked in at INSERT time
        -- not in merge_update_columns → never overwritten
        s.lifecycle_stage,
        s.days_to_first_payment,
        s.first_payment_cohort,
        s.total_payments,

        -- consumption
        coalesce(lm.hours_booked_so_far, 0)     as hours_booked_so_far,
        greatest(
            c.hours_purchased
            - coalesce(lm.hours_booked_so_far, 0), 0
        )                                       as hours_remaining,
        coalesce(lm.lessons_count, 0)           as lessons_count,
        lm.last_booking_date,

        -- daily burn rate
        case
            when c.days_elapsed = 0 then null
            else round(
                coalesce(lm.hours_booked_so_far, 0)
                / c.days_elapsed, 4
            )
        end                                     as daily_burn_rate,

        -- fully booked flag
        case
            when coalesce(lm.hours_booked_so_far, 0)
                >= c.hours_purchased
            then true else false
        end                                     as is_fully_booked,

        hr.avg_breakage_rate                    as historical_avg_breakage_rate,
        oar.overall_avg_breakage_rate,

        -- actual breakage
        {{ actual_breakage_hours(
            'c.cycle_status',
            'c.hours_purchased',
            'coalesce(lm.hours_booked_so_far, 0)'
        ) }}                                    as actual_breakage_hours,

        -- estimated breakage
        {{ estimated_breakage_hours(
            'c.cycle_status',
            'case when coalesce(lm.hours_booked_so_far,0) >= c.hours_purchased then true else false end',
            'c.days_elapsed',
            'c.hours_purchased',
            'case when c.days_elapsed = 0 then null else coalesce(lm.hours_booked_so_far,0) / c.days_elapsed end',
            'hr.avg_breakage_rate',
            'oar.overall_avg_breakage_rate'
        ) }}                                    as estimated_breakage_hours,

        -- estimation method
        {{ estimation_method(
            'c.cycle_status',
            'case when coalesce(lm.hours_booked_so_far,0) >= c.hours_purchased then true else false end',
            'c.days_elapsed'
        ) }}                                    as estimation_method,
        case
            when coalesce(lm.hours_booked_so_far, 0) > c.hours_purchased
            then true else false
        end as is_overbooked

    from cycles c
    left join lessons_mapped lm
        on c.payment_id = lm.payment_id
    left join students s
        on c.student_id = s.student_id
    left join historical_rates hr
        on c.hours_purchased = hr.plan_size
    cross join overall_rate oar
)

select
    payment_id,
    student_id,
    cycle_start,
    cycle_end,
    cycle_status,
    days_elapsed,
    days_remaining,
    hours_purchased,
    price_per_hour_usd,
    total_plan_value_usd,
    student_type,
    cycle_number,
    country_code,
    persona,
    acquisition_channel,
    first_subject,
    join_cohort,
    payment_cohort,
    join_date,
    lifecycle_stage,
    days_to_first_payment,
    first_payment_cohort,
    total_payments,
    hours_booked_so_far,
    hours_remaining,
    lessons_count,
    last_booking_date,
    daily_burn_rate,
    is_fully_booked,
    historical_avg_breakage_rate,
    overall_avg_breakage_rate,
    estimation_method,
    actual_breakage_hours,
    estimated_breakage_hours,

    coalesce(
        actual_breakage_hours,
        estimated_breakage_hours
    )                                           as breakage_hours,

    round(actual_breakage_hours
        * price_per_hour_usd, 2)               as actual_breakage_usd,

    round(estimated_breakage_hours
        * price_per_hour_usd, 2)               as estimated_breakage_usd,

    round(coalesce(
        actual_breakage_hours,
        estimated_breakage_hours
    ) * price_per_hour_usd, 2)                 as breakage_usd,

    case
        when cycle_status = 'closed'
        then false else true
    end                                         as is_estimate,

-- commission — capped at hours_purchased
    {{ commission_usd(
        'coalesce(hours_booked_so_far, 0)',
        'hours_purchased',
        'price_per_hour_usd'
    ) }}                                    as commission_usd,

    -- total revenue
    {{ total_revenue_usd(
        'coalesce(hours_booked_so_far, 0)',
        'hours_purchased',
        'price_per_hour_usd',
        'actual_breakage_hours',
        'estimated_breakage_hours'
    ) }}                                    as total_revenue_usd,

    current_timestamp()                         as updated_at

from joined

{% if is_incremental() %}
where cycle_start >= cast('{{ var("as_of_date") }}' as date)
    - interval {{ var('cycle_length_days') }} days
{% endif %}