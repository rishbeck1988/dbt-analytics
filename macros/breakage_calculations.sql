{% macro historical_rates_cte(cycles_cte='cycles', lessons_cte='lessons_mapped') %}
historical_rates as (
    select
        c.hours_purchased                       as plan_size,
        round(avg(
            greatest(
                c.hours_purchased
                - coalesce(lm.hours_booked_so_far, 0), 0
            ) / nullif(c.hours_purchased, 0)
        ), 4)                                   as avg_breakage_rate
    from {{ cycles_cte }} c
    left join {{ lessons_cte }} lm
        on c.payment_id = lm.payment_id
    where c.cycle_status = 'closed'
    group by c.hours_purchased
),

overall_rate as (
    select round(avg(
        greatest(
            c.hours_purchased
            - coalesce(lm.hours_booked_so_far, 0), 0
        ) / nullif(c.hours_purchased, 0)
    ), 4)                                       as overall_avg_breakage_rate
    from {{ cycles_cte }} c
    left join {{ lessons_cte }} lm
        on c.payment_id = lm.payment_id
    where c.cycle_status = 'closed'
)
{% endmacro %}


{% macro actual_breakage_hours(
    cycle_status,
    hours_purchased,
    hours_booked_so_far
) %}
case
    when {{ cycle_status }} = 'closed'
    then greatest(
        {{ hours_purchased }} - {{ hours_booked_so_far }}, 0
    )
    else null
end
{% endmacro %}


{% macro estimated_breakage_hours(
    cycle_status,
    is_fully_booked,
    days_elapsed,
    hours_purchased,
    daily_burn_rate,
    historical_avg_breakage_rate,
    overall_avg_breakage_rate
) %}
case
    when {{ cycle_status }} = 'open'
     and {{ is_fully_booked }} = true
    then 0

    when {{ cycle_status }} = 'open'
     and {{ days_elapsed }} = 0
    then round(
        {{ hours_purchased }} * coalesce(
            {{ historical_avg_breakage_rate }},
            {{ overall_avg_breakage_rate }}
        ), 2
    )

    when {{ cycle_status }} = 'open'
    then greatest(
        {{ hours_purchased }} - (
            {{ daily_burn_rate }}
            * {{ var('cycle_length_days') }}
        ), 0
    )

    else null
end
{% endmacro %}


{% macro estimation_method(
    cycle_status,
    is_fully_booked,
    days_elapsed
) %}
case
    when {{ cycle_status }} = 'closed'      then 'actual'
    when {{ is_fully_booked }} = true       then 'fully_booked_zero'
    when {{ days_elapsed }} = 0             then 'historical_rate_fallback'
    else                                         'burn_rate_projection'
end
{% endmacro %}

{% macro commission_usd(
    hours_booked_so_far,
    hours_purchased,
    price_per_hour_usd
) %}
round(
    least(
        {{ hours_booked_so_far }},
        {{ hours_purchased }}
    )
    * {{ price_per_hour_usd }}
    * 0.20, 2
)
{% endmacro %}


{% macro total_revenue_usd(
    hours_booked_so_far,
    hours_purchased,
    price_per_hour_usd,
    actual_breakage_hours,
    estimated_breakage_hours
) %}
round(
    least(
        {{ hours_booked_so_far }},
        {{ hours_purchased }}
    )
    * {{ price_per_hour_usd }} * 0.20
    + coalesce(
        {{ actual_breakage_hours }},
        {{ estimated_breakage_hours }}
    ) * {{ price_per_hour_usd }}, 2
)
{% endmacro %}