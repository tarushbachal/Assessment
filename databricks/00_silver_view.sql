-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 00 · Silver View — the SQL twin of `silver.py`
-- MAGIC
-- MAGIC Builds `workspace.default.appointment_clean` from the bronze table
-- MAGIC `workspace.default.appointment_data`. Every dashboard tile reads this one view, so the
-- MAGIC cleaning logic and business definitions live in exactly one governed place.
-- MAGIC
-- MAGIC **Two data quirks handled here (same as the Python pipeline):**
-- MAGIC 1. Split date/time placeholders — the `*_DATE` columns carry a fake time, the `*_TIME` columns a
-- MAGIC    fake date (`12/30/99`). We read the date from `*_DATE` and the clock time from `*_TIME`.
-- MAGIC 2. `SHOW_CODE` has three values `Y`/`N`/`P`; `N` and `P` are both no-shows.
-- MAGIC
-- MAGIC The parse is written defensively with `try_to_timestamp` on two formats, so it works whether the
-- MAGIC bronze columns were loaded as **strings** (`MM/dd/yy HH:mm:ss`) or auto-typed as **timestamps**
-- MAGIC (`yyyy-MM-dd HH:mm:ss`). Run this once; re-run any time to refresh the definition.

-- COMMAND ----------

CREATE OR REPLACE VIEW workspace.default.appointment_clean AS
WITH parsed AS (
  SELECT
    FACILITY,
    DEPARTMENT,
    PROVIDER_ID,
    PATIENT_ID,
    APPOINTMENT_TYPE,
    SHOW_CODE,
    -- Real clock time (its date part is the fake 12/30/99 placeholder)
    coalesce(try_to_timestamp(CAST(APPOINTMENT_TIME AS STRING), 'MM/dd/yy HH:mm:ss'),
             try_to_timestamp(CAST(APPOINTMENT_TIME AS STRING), 'yyyy-MM-dd HH:mm:ss')) AS appt_ts,
    -- Real appointment date (its time part is the fake 00:00:00 placeholder)
    coalesce(try_to_timestamp(CAST(APPOINTMENT_DATE AS STRING), 'MM/dd/yy HH:mm:ss'),
             try_to_timestamp(CAST(APPOINTMENT_DATE AS STRING), 'yyyy-MM-dd HH:mm:ss')) AS appt_date_ts,
    coalesce(try_to_timestamp(CAST(BOOKING_TIME AS STRING), 'MM/dd/yy HH:mm:ss'),
             try_to_timestamp(CAST(BOOKING_TIME AS STRING), 'yyyy-MM-dd HH:mm:ss')) AS booking_ts,
    coalesce(try_to_timestamp(CAST(BOOKING_DATE AS STRING), 'MM/dd/yy HH:mm:ss'),
             try_to_timestamp(CAST(BOOKING_DATE AS STRING), 'yyyy-MM-dd HH:mm:ss')) AS booking_date_ts
  FROM workspace.default.appointment_data
)
SELECT
  PROVIDER_ID,
  PATIENT_ID,
  APPOINTMENT_TYPE,
  SHOW_CODE,
  CAST(appt_date_ts AS DATE)                                   AS appt_date,
  CAST(booking_date_ts AS DATE)                                AS booking_date,
  -- minutes-since-midnight is the workhorse for every time filter / bucket
  hour(appt_ts) * 60 + minute(appt_ts)                         AS appt_min_of_day,
  hour(appt_ts)                                                AS appt_hour,
  hour(booking_ts) * 60 + minute(booking_ts)                   AS booking_min_of_day,
  date_format(appt_date_ts, 'EEEE')                            AS day_of_week,
  weekday(appt_date_ts)                                        AS dow_num,     -- 0=Mon ... 6=Sun (for ordering)
  date_format(appt_date_ts, 'yyyy-MM')                         AS appt_month,
  -- business flags stored as 1/0 so SUM()/AVG() work directly in the dashboard queries
  CASE WHEN APPOINTMENT_TYPE = 'Telephone Visit' THEN 1 ELSE 0 END                     AS is_telephone,
  CASE WHEN hour(appt_ts) * 60 + minute(appt_ts) >= 1050 THEN 1 ELSE 0 END             AS is_after_hours,   -- >= 17:30
  CASE WHEN weekday(appt_date_ts) >= 5 THEN 1 ELSE 0 END                               AS is_weekend,       -- Sat/Sun
  CASE WHEN SHOW_CODE = 'Y' THEN 1 ELSE 0 END                                          AS is_completed,
  CASE WHEN SHOW_CODE IN ('N', 'P') THEN 1 ELSE 0 END                                  AS is_noshow,
  datediff(CAST(appt_date_ts AS DATE), CAST(booking_date_ts AS DATE))                  AS lead_days,
  -- same-day booking lead in minutes only (null when booked a different day)
  CASE WHEN datediff(CAST(appt_date_ts AS DATE), CAST(booking_date_ts AS DATE)) = 0
       THEN (hour(appt_ts) * 60 + minute(appt_ts)) - (hour(booking_ts) * 60 + minute(booking_ts))
       ELSE NULL END                                                                   AS booking_lead_min
FROM parsed;

-- COMMAND ----------

-- MAGIC %md ### Sanity check — should read 125,053 rows, 4,383 after-hours telephone, 19.4% no-show
SELECT
  COUNT(*)                                                                    AS rows,
  SUM(is_telephone * is_after_hours)                                          AS after_hours_telephone,
  ROUND(AVG(CASE WHEN is_telephone = 1 AND is_after_hours = 1 THEN is_noshow END) * 100, 1) AS ah_tel_noshow_pct,
  MIN(appt_date) AS first_date, MAX(appt_date) AS last_date
FROM workspace.default.appointment_clean;
