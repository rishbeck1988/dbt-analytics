# Preply Analytics — Breakage Estimation

A dbt project that estimates and tracks breakage revenue for Preply's PayOps team.

**Breakage** = hours purchased but unused at the end of a 28-day subscription cycle.
The pipeline produces both **actual breakage** (closed cycles) and **estimated breakage** (open cycles), refreshed daily.

---

## Quickstart

### Prerequisites
- Python 3.11
- dbt-databricks >= 1.11
- Databricks workspace with Unity Catalog

### Setup
```bash
git clone <repo>
cd preply_analytics
pip install dbt-databricks
dbt debug                         # verify connection
```

### Run
```bash
dbt seed                          # load raw CSVs into Databricks
dbt run --select staging          # clean source data
dbt run --select intermediate     # business logic
dbt run --select marts            # final tables
dbt test                          # run all tests
```

### Run everything at once
```bash
dbt build                         # seed + run + test in dependency order
```

### Variables
| Variable | Default | Description |
|---|---|---|
| `as_of_date` | `2026-04-17` | Point-in-time date — set to `current_date()` in production |
| `cycle_length_days` | `28` | Subscription cycle length — change here only |

Override:
```bash
dbt run --vars '{"as_of_date": "2026-05-01", "cycle_length_days": 28}'
```

---

## Data model

### DAG
```
raw_students ──► stg_students ─────────────────────────────────────────────┐
raw_payments ──► stg_payments ──► int_payment_cycles ──────────────────────►├──► int_breakage_estimates ──► fct_payments
raw_lessons  ──► stg_lessons  ──► int_lessons_per_cycle ───────────────────┘                               fct_breakage_daily
                                                                                                            dim_students
```

### Layers

#### Staging — views
Clean and filter raw source data. No business logic.

| Model | Grain | Notes |
|---|---|---|
| `stg_students` | one row per student | lowercase strings, filter nulls |
| `stg_payments` | one row per payment | rename hours → hours_purchased, add total_plan_value_usd |
| `stg_lessons` | one row per lesson | filter hours_booked <= 0 and nulls |

#### Intermediate — views
Encode all business logic. Recompute fully on every dbt run.

| Model | Grain | Notes |
|---|---|---|
| `int_payment_cycles` | one row per payment | cycle boundaries, open/closed status, student dimensions |
| `int_lessons_per_cycle` | one row per payment | hours burned, daily burn rate, is_fully_booked |
| `int_breakage_estimates` | one row per payment | all breakage math — actual, estimated, commission, total revenue |

#### Marts — tables
Final tables powering the dashboard.

| Model | Grain | Materialization | Purpose |
|---|---|---|---|
| `dim_students` | one row per student | table, full refresh | student segments and cohorts |
| `fct_payments` | one row per payment | incremental, merge | current state — PayOps headline metrics |
| `fct_breakage_daily` | one row per payment per day | incremental, append | daily trends and estimate evolution |

---

## Approach

### Estimation formula
Breakage is estimated differently depending on days elapsed in the cycle:

| Method | When | Formula |
|---|---|---|
| `actual` | cycle closed | `hours_purchased - hours_booked` |
| `fully_booked_zero` | all hours used | `0` |
| `historical_rate_fallback` | day 0 | `hours_purchased × avg_breakage_rate_for_plan_size` |
| `burn_rate_projection` | days 1–27 | `max(hours_purchased - (daily_burn_rate × 28), 0)` |

Day 0 fallback uses the historical average breakage rate for that plan size from closed cycles.
If no plan-specific rate exists, the overall portfolio average is used — no hardcoded constants.

### Revenue model
```
Commission     = 20% × hours_booked × price_per_hour
Breakage       = 100% × hours_unbooked × price_per_hour
Total revenue  = commission + breakage
```

### Aggregation rules
```
✅ SUM breakage_usd across payments on same snapshot_date  → valid
✅ SUM actual_breakage_usd across all closed cycles        → valid
❌ SUM estimated_breakage_usd across days for same payment → double counting
```

---

## Key assumptions

- **Cycle anchor:** cycle starts on payment date, ends exactly `cycle_length_days` later
- **Lesson mapping:** lessons mapped to cycles via student_id + booking_date within cycle window
- **Student dimensions:** SCD Type 1 — current values only. If a student changes country, all historical payments reflect the new value. Sufficient for PayOps operational segmentation.
- **No cancellations:** bookings are final per the case study specification
- **as_of_date:** fixed at 2026-04-17 to match dataset; switch to `current_date()` for production

---

## Tests

### Run tests
```bash
dbt test                          # all tests
dbt test --select staging         # staging only
dbt test --select marts           # marts only
```

### Schema tests
- `unique` and `not_null` on all primary keys
- `accepted_values` on `cycle_status`, `hours_purchased`, `estimation_method`
- `relationships` between payments/lessons and students

### Custom business logic tests
| Test | What it checks |
|---|---|
| `no_overbooking` | hours_booked_so_far never exceeds hours_purchased |
| `cycle_length_check` | cycle_end is exactly cycle_length_days after cycle_start |
| `no_negative_breakage` | breakage_hours never negative |

---

## Dashboard

The dashboard answers:
- What is total expected breakage revenue today — actual vs estimated?
- How has the estimate for a payment cohort evolved over time?
- Which segments (plan size, country, persona, new vs returning) have highest breakage?

See `/dashboard` for the mockup.

---

## Caveats

- Day 0 estimates are least accurate — based on historical averages, not actual burn data
- Estimated breakage accuracy improves as days_elapsed increases
- `total_revenue_usd` on open cycles is not recognised revenue — not for financial reporting
- Student segments reflect current attributes — historical attribute changes not tracked

---

## What I'd build next

- **`fct_breakage_daily` convergence analysis** — plot how estimates improve toward actual over 28 days
- **SCD Type 2 on `dim_students`** — using dbt snapshots for historically accurate segment attribution
- **Rejection audit tables** — `stg_*_rejected` to capture and alert on invalid source rows
- **Elementary integration** — automated data health dashboard decoupled from transformation pipeline
- **Airflow DAG** — `dbt run → dbt test` sequenced daily with alerting on test failures
- **Confidence intervals** — breakage estimate ranges using historical variance by plan size
- **Finance recognition view** — breakage by recognition date for accounting reconciliation

---

## AI usage note

### Where AI helped
- Scaffolding dbt project structure and boilerplate SQL
- Suggesting the `estimation_method` column for debuggability
- Generating the dashboard mockup HTML
- Drafting README structure

### Where I rejected or corrected AI output
- AI initially suggested hardcoding `0.25` as fallback breakage rate — replaced with data-driven overall portfolio average
- AI suggested SCD Type 2 for students — simplified to Type 1 after evaluating trade-offs for this use case
- AI over-engineered DQ with separate model layer — simplified to WHERE clause in staging + schema tests
- AI suggested `fct_breakage_daily` with 28 rows per closed payment — corrected to one row per closed cycle only

### How I verified
- Ran exploratory SQL in Databricks before writing any dbt models
- Checked row counts at each layer (seeds → staging → intermediate)
- Manually verified breakage calculation against assignment example ($80 plan, 6 booked, 2 unbooked = $12 commission + $20 breakage)
- Cross-checked open vs closed cycle counts against expected ~850 open / ~8,850 closed split

