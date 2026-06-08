select
    student_id,
    join_ts,
    date(join_ts)                           as join_date,
    lower(trim(country_code))              as country_code,
    lower(trim(acquisition_channel))       as acquisition_channel,
    lower(trim(persona))                   as persona,
    lower(trim(first_subject))             as first_subject
from {{ ref('raw_students') }}
where student_id is not null
  and join_ts is not null