select
    lesson_id,
    student_id,
    booking_ts,
    date(booking_ts) as booking_date,
    hours_booked
from {{ ref('raw_lessons') }}
where hours_booked > 0
  and lesson_id is not null
  and student_id is not null
  and booking_ts is not null