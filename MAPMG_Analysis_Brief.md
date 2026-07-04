# MAPMG Data Analyst Assessment — Analysis Brief
**For Claude Code: Read this fully before writing any code or queries.**

---

## Context

This is a job interview take-home assessment for a **Data Analyst role at Mid-Atlantic Permanente Medical Group (MAPMG)**. The panel discussion is 1 hour with the analytics team. The candidate is comfortable with SQL, Python (understands it), and Databricks. MAPMG is actively migrating to Databricks, so the entire workflow is built on Databricks Free Trial.

The data has been ingested from a `.mdb` (Microsoft Access) file, exported to CSV, uploaded to a Databricks Unity Catalog Volume, and registered as a Delta table at:

```
workspace.edv_bronze.appointment_data
```

A **data dictionary** will be provided as a separate file. Read it before writing any queries — use it to understand column names, codes, and their meanings.

---

## The Three Assessment Questions

### Q1: How many physicians would you need to staff the after-hours (after 17:30) telephone clinic?

**Goal:** Produce a defensible staffing recommendation with supporting data.

**Analysis to run:**
- Filter all appointments where the scheduled time is after 17:30
- Determine the volume of after-hours telephone appointments by:
  - Day of week (Mon–Sun)
  - Hour of day (17:30, 18:00, 18:30, etc.)
  - Month/season (are there volume spikes?)
- Calculate average, peak (95th percentile), and median appointment counts per time slot
- Estimate average handle time per appointment if a duration column exists (end time - start time)
- Calculate total physician-hours needed per shift window
- Apply a standard utilization assumption (e.g., 80% utilization per physician per hour) to arrive at FTE count
- Distinguish between:
  - **Minimum staffing** (covers average demand)
  - **Recommended staffing** (covers 90th percentile demand — avoids patient wait time spikes)
  - **Peak staffing** (covers maximum observed demand)
- If appointment status codes exist (completed, cancelled, no-show), factor out non-completed appointments from demand calculations
- Present final recommendation as: *"X physicians on weekdays, Y on weekends, with Z as a surge buffer"*

**SQL starting point:**
```sql
-- After-hours telephone appointment volume by day and hour
SELECT
  DAYOFWEEK(appointment_date) AS day_of_week,
  HOUR(appointment_time) AS hour_of_day,
  COUNT(*) AS total_appointments,
  COUNT(DISTINCT physician_id) AS physicians_used
FROM workspace.edv_bronze.appointment_data
WHERE appointment_time > '17:30:00'
  AND appointment_type LIKE '%telephone%'  -- adjust column/value to match data dictionary
GROUP BY 1, 2
ORDER BY 1, 2;
```
> Note: Adjust column names based on the data dictionary. Do not assume column names — verify them first with `DESCRIBE workspace.edv_bronze.appointment_data`.

---

### Q2: How effective are the Telephone Appointments during after-hours?

**Goal:** Measure effectiveness using available data signals. Effectiveness = whether the appointment achieved its intended purpose.

**Metrics to calculate (use whichever columns are available):**
- **Completion rate** — % of scheduled after-hours telephone appointments that were completed vs. cancelled/no-show/rescheduled
- **No-show rate** — % that resulted in patient no-show
- **Cancellation rate** — % cancelled (by patient vs. by clinic, if distinguishable)
- **Reschedule rate** — % that had to be rescheduled to another time slot
- **Same-day resolution rate** — % of after-hours calls that did not require a follow-up in-person visit within X days (if visit data is available)
- **Volume trend** — Are after-hours telephone appointments increasing or decreasing over time? (signals demand and adoption)
- **Physician utilization** — Are after-hours slots being fully booked or underutilized? (scheduled vs. available capacity)
- **Patient-to-physician ratio** — Average appointment load per physician per shift

**Benchmarking:**
- Compare after-hours telephone completion rate vs. daytime telephone completion rate
- Compare after-hours telephone no-show rate vs. in-person no-show rate
- This gives context — are after-hours calls underperforming relative to other modalities?

**SQL starting point:**
```sql
-- Completion rate: after-hours telephone vs. all telephone
SELECT
  CASE WHEN appointment_time > '17:30:00' THEN 'After Hours' ELSE 'During Hours' END AS time_bucket,
  appointment_status,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY CASE WHEN appointment_time > '17:30:00' THEN 'After Hours' ELSE 'During Hours' END), 2) AS pct
FROM workspace.edv_bronze.appointment_data
WHERE appointment_type LIKE '%telephone%'
GROUP BY 1, 2
ORDER BY 1, 2;
```

---

### Q3: What suggestions would you make to improve after-hours telephone appointment effectiveness?

**Goal:** This is the strategic/synthesis question. Your suggestions must be grounded in the data from Q1 and Q2 — not generic best practices alone.

**Analysis to run first (to support suggestions):**
- Identify the hours/days with highest no-show rates — are there patterns? (e.g., Friday evenings worse than Monday evenings?)
- Identify if certain physicians have significantly better completion rates — if so, what might explain it?
- Look at lead time: are appointments booked same-day vs. days in advance? Does lead time correlate with no-show?
- Look at appointment duration distribution — are some calls running long and backing up the queue?
- Check if any patient demographics or appointment reason codes (if available) correlate with no-show or cancellation

**Suggestion framework (data-driven, not generic):**
1. **Staffing optimization** — Based on Q1 findings, shift physician allocation toward peak-demand hours/days
2. **Demand smoothing** — If Friday evenings have low volume, consider incentivizing patients to book earlier in the week
3. **No-show reduction** — If no-show rate is high, recommend automated reminders (text/call) 2 hours before after-hours slot
4. **Slot duration calibration** — If average handle time exceeds scheduled slot length, recommend adjusting default slot length
5. **Utilization floor** — If slots are consistently underbooked, recommend reducing total after-hours capacity on low-demand nights
6. **Follow-up reduction metric** — If many after-hours calls result in next-day in-person visits, investigate whether the telephone visit is resolving issues or deferring them

---

## Data Preparation Steps (Run First)

Before any analysis, run these in a Databricks notebook in order:

### Step 1: Inspect the schema
```sql
DESCRIBE workspace.edv_bronze.appointment_data;
```

### Step 2: Preview the data
```sql
SELECT * FROM workspace.edv_bronze.appointment_data LIMIT 20;
```

### Step 3: Row count and date range
```sql
SELECT
  COUNT(*) AS total_rows,
  MIN(appointment_date) AS earliest_date,
  MAX(appointment_date) AS latest_date,
  COUNT(DISTINCT physician_id) AS unique_physicians,
  COUNT(DISTINCT patient_id) AS unique_patients
FROM workspace.edv_bronze.appointment_data;
```
> Replace column names with actual names from the data dictionary.

### Step 4: Null check on key columns
```sql
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN appointment_time IS NULL THEN 1 ELSE 0 END) AS null_appt_time,
  SUM(CASE WHEN appointment_date IS NULL THEN 1 ELSE 0 END) AS null_appt_date,
  SUM(CASE WHEN appointment_type IS NULL THEN 1 ELSE 0 END) AS null_appt_type,
  SUM(CASE WHEN appointment_status IS NULL THEN 1 ELSE 0 END) AS null_status
FROM workspace.edv_bronze.appointment_data;
```

### Step 5: Appointment type distribution
```sql
SELECT appointment_type, COUNT(*) AS cnt
FROM workspace.edv_bronze.appointment_data
GROUP BY 1
ORDER BY 2 DESC;
```
This tells you what the telephone appointment type code/label actually is so you can filter correctly.

### Step 6: Status code distribution
```sql
SELECT appointment_status, COUNT(*) AS cnt
FROM workspace.edv_bronze.appointment_data
GROUP BY 1
ORDER BY 2 DESC;
```

---

## Deliverables Expected

Claude Code should produce:

1. **A profiling notebook** — schema, nulls, distributions, date range (Steps 1–6 above)
2. **An analysis notebook** — one section per question (Q1, Q2, Q3), with SQL queries, results, and written interpretation of each finding
3. **A summary findings doc** — 1-page narrative suitable for the panel: key numbers, methodology note, and 3–5 bullet recommendations
4. **Dashboard-ready query set** — clean, final SQL queries for Q1 and Q2 metrics that can be pasted into Databricks SQL Dashboard builder

All code should be written in **Databricks SQL** as the primary language. Use **Python (PySpark or pandas)** only when SQL is insufficient (e.g., percentile calculations, time bucketing, visualization).

---

## Constraints and Notes

- **After-hours = appointment time after 17:30** (5:30 PM)
- **Telephone appointments** — filter by appointment type column; check data dictionary for exact code/label
- **Do not hardcode column names** — always verify against `DESCRIBE` output and the data dictionary first
- **Flag assumptions explicitly** — if a column's meaning is ambiguous, state the assumption made before using it
- **No-show, cancelled, rescheduled** — treat these as separate statuses; do not lump together unless the data dictionary says otherwise
- **Staffing math** — assume a physician can handle 1 appointment per slot; adjust if average duration data suggests otherwise
- **Data dictionary is authoritative** — if the data dictionary contradicts any assumption in this brief, follow the data dictionary

---

## For the Panel Discussion

The panel will likely ask:
- "Walk us through how you approached the staffing question" — lead with methodology (peak vs. average demand), then the number
- "What data would you want that you didn't have?" — good answers: patient acuity, call duration, reason for cancellation, patient callback data
- "How would this scale in production?" — mention Delta tables, scheduled Databricks Jobs, Unity Catalog governance, Genie for self-serve analytics
- "What surprised you in the data?" — have one genuine finding ready

The candidate is comfortable with Databricks and aware that MAPMG is migrating to it — lean into this. Frame every deliverable as production-ready, not just an ad hoc analysis.

---

*This brief was prepared to guide automated analysis via Claude Code. All column names and filter values should be validated against the actual schema and data dictionary before running.*
