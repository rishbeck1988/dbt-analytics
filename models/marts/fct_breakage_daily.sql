{{
    config(
        materialized='incremental',
        unique_key=['payment_id', 'snapshot_date'],
        incremental_strategy='merge',
        merge_update_columns=[
            'cycle_status',
            'hours_booked_so_far',
            'hours_remaining',
            'daily_burn_rate',
            'is_fully_booked',
            'breakage_hours',
            'breakage_usd',
            'actual_breakage_hours',
            'actual_breakage_usd',
            'estimated_breakage_hours',
            'estimated_breakage_usd',
            'commission_usd',
            'total_revenue_usd',
            'is_estimate',
            'estimation_method',
            'updated_at'
        ]
    )
}}

with cycles as (
    select * from {{ ref('int_payment_cycles') }}
),

lessons as (
    select * from {{ ref('stg_lessons') }}
),

-- generate one row per day per payment
-- capped at as_of_date — no future rows
date_spine as (
    select
        c.payment_id,
        c.student_id,
        c.cycle_start,
        c.cycle_end,
        c.hours_purchased,
        c.price_per_hour_usd,
        c.total_plan_value_usd,
        c.student_type,
        c.cycle_number,
        c.country_code,
        c.persona,
        c.acquisition_channel,
        c.payment_cohort,
        explode(
            sequence(
                c.cycle_start,
                least(
                    c.cycle_end,
                    cast('{{ var("as_of_date") }}' as date)
                ),
                interval 1 day
            )
        )                                       as snapshot_date
    from cycles c
),

-- cumulative hours booked as of each snapshot_date
cumulative_lessons as (
    select
        ds.payment_id,
        ds.snapshot_date,
        coalesce(sum(l.hours_booked), 0)        as hours_booked_so_far
    from date_spine ds
    left join lessons l
        on  l.student_id    = ds.student_id
        and l.booking_date  >= ds.cycle_start
        and l.booking_date  <= ds.snapshot_date
    group by
        ds.payment_id,
        ds.snapshot_date
),

-- day level metrics
daily_calc as (
    select
        ds.payment_id,
        ds.student_id,
        ds.snapshot_date,
        ds.cycle_start,
        ds.cycle_end,
        ds.hours_purchased,
        ds.price_per_hour_usd,
        ds.total_plan_value_usd,
        ds.student_type,
        ds.cycle_number,
        ds.country_code,
        ds.persona,
        ds.acquisition_channel,
        ds.payment_cohort,
        cl.hours_booked_so_far,

        greatest(
            ds.hours_purchased - cl.hours_booked_so_far, 0
        )                                       as hours_remaining,

        datediff(
            ds.snapshot_date, ds.cycle_start
        )                                       as days_elapsed,

        datediff(
            ds.cycle_end, ds.snapshot_date
        )                                       as days_remaining,

        case
            when ds.snapshot_date = ds.cycle_end
            then 'closed' else 'open'
        end                                     as cycle_status,

        case
            when cl.hours_booked_so_far >= ds.hours_purchased
            then true else false
        end                                     as is_fully_booked,

        case
            when datediff(ds.snapshot_date, ds.cycle_start) = 0
            then null
            else round(
                cl.hours_booked_so_far
                / datediff(ds.snapshot_date, ds.cycle_start), 4
            )
        end                                     as daily_burn_rate

    from date_spine ds
    left join cumulative_lessons cl
        on  ds.payment_id    = cl.payment_id
        and ds.snapshot_date = cl.snapshot_date
),

-- closed cycle totals for historical rate calculation
-- use final day of each closed cycle as the actual total
lessons_mapped as (
    select
        payment_id,
        hours_booked_so_far
    from daily_calc
    where snapshot_date = cycle_end
      and cycle_status = 'closed'
),

-- historical rates using macro
-- explicit CTE names passed — no hidden assumptions
{{ historical_rates_cte('cycles', 'lessons_mapped') }},

-- breakage calculation per day
breakage_calc as (
    select
        dc.*,
        hr.avg_breakage_rate                    as historical_avg_breakage_rate,
        oar.overall_avg_breakage_rate,

        {{ actual_breakage_hours(
            'dc.cycle_status',
            'dc.hours_purchased',
            'dc.hours_booked_so_far'
        ) }}                                    as actual_breakage_hours,

        {{ estimated_breakage_hours(
            'dc.cycle_status',
            'dc.is_fully_booked',
            'dc.days_elapsed',
            'dc.hours_purchased',
            'dc.daily_burn_rate',
            'hr.avg_breakage_rate',
            'oar.overall_avg_breakage_rate'
        ) }}                                    as estimated_breakage_hours,

        {{ estimation_method(
            'dc.cycle_status',
            'dc.is_fully_booked',
            'dc.days_elapsed'
        ) }}                                    as estimation_method

    from daily_calc dc
    left join historical_rates hr
        on dc.hours_purchased = hr.plan_size
    cross join overall_rate oar
)

select
    payment_id,
    snapshot_date,
    student_id,
    cycle_start,
    cycle_end,
    cycle_status,
    days_elapsed,
    days_remaining,
    hours_purchased,
    price_per_hour_usd,
    hours_booked_so_far,
    hours_remaining,
    daily_burn_rate,
    is_fully_booked,
    estimation_method,
    student_type,
    cycle_number,
    country_code,
    persona,
    acquisition_channel,
    payment_cohort,
    historical_avg_breakage_rate,
    overall_avg_breakage_rate,

    actual_breakage_hours,
    round(actual_breakage_hours
        * price_per_hour_usd, 2)               as actual_breakage_usd,

    estimated_breakage_hours,
    round(estimated_breakage_hours
        * price_per_hour_usd, 2)               as estimated_breakage_usd,

    coalesce(
        actual_breakage_hours,
        estimated_breakage_hours
    )                                           as breakage_hours,

    round(coalesce(
        actual_breakage_hours,
        estimated_breakage_hours
    ) * price_per_hour_usd, 2)                 as breakage_usd,

    case
        when cycle_status = 'closed'
        then false else true
    end                                         as is_estimate,

    {{ commission_usd(
        'hours_booked_so_far',
        'hours_purchased',
        'price_per_hour_usd'
    ) }}                                    as commission_usd,

    {{ total_revenue_usd(
        'hours_booked_so_far',
        'hours_purchased',
        'price_per_hour_usd',
        'actual_breakage_hours',
        'estimated_breakage_hours'
    ) }}                                    as total_revenue_usd,

    current_timestamp()                         as updated_at

from breakage_calc

{% if is_incremental() %}
where snapshot_date >= (
    select dateadd(day, 1, max(snapshot_date))
    from {{ this }}
)
and snapshot_date <= cast('{{ var("as_of_date") }}' as date)
{% endif %}