-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Dashboard tile queries (Databricks SQL)
-- MAGIC
-- MAGIC One query = one dashboard tile. All read `workspace.default.appointment_clean`. These are the
-- MAGIC same queries embedded as datasets in `after_hours.lvdash.json` — kept here so you can run/verify
-- MAGIC each one in the SQL editor before wiring the dashboard.

-- COMMAND ----------

-- TILE 1 · KPI strip
SELECT
  SUM(is_telephone * is_after_hours)                                                              AS after_hours_telephone_appts,
  ROUND(AVG(CASE WHEN is_telephone = 1 AND is_after_hours = 1 THEN is_noshow END) * 100, 1)       AS ah_tel_noshow_pct,
  ROUND(AVG(CASE WHEN is_after_hours = 1 AND is_telephone = 0 THEN is_noshow END) * 100, 1)       AS ah_inperson_noshow_pct,
  ROUND(SUM(is_telephone * is_after_hours) * 100.0 / SUM(is_after_hours), 1)                      AS telephone_share_of_ah_pct
FROM workspace.default.appointment_clean;

-- COMMAND ----------

-- TILE 2 · Demand heatmap — after-hours telephone volume by day & hour
SELECT day_of_week, dow_num, appt_hour, SUM(is_completed) AS completed_appts
FROM workspace.default.appointment_clean
WHERE is_telephone = 1 AND is_after_hours = 1
GROUP BY day_of_week, dow_num, appt_hour
ORDER BY dow_num, appt_hour;

-- COMMAND ----------

-- TILE 3 · Staffing curve — physicians needed by day type (min / recommended / peak)
WITH window_load AS (
  SELECT appt_date, is_weekend, FLOOR(appt_min_of_day / 30) AS win30, COUNT(*) AS load
  FROM workspace.default.appointment_clean
  WHERE is_telephone = 1 AND is_after_hours = 1 AND is_completed = 1
  GROUP BY appt_date, is_weekend, FLOOR(appt_min_of_day / 30)
),
evening_peak AS (
  SELECT appt_date, is_weekend, MAX(load) AS peak FROM window_load GROUP BY appt_date, is_weekend
)
SELECT
  CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
  CEIL(percentile(peak, 0.5)  / 3.0) AS minimum,
  CEIL(percentile(peak, 0.95) / 3.0) AS recommended,
  CEIL(MAX(peak)              / 3.0) AS peak
FROM evening_peak
GROUP BY is_weekend
ORDER BY is_weekend;

-- COMMAND ----------

-- TILE 4 · No-show by booking lead (the actionable driver)
SELECT
  CASE
    WHEN booking_lead_min < 30  THEN '1 · <30 min'
    WHEN booking_lead_min < 60  THEN '2 · 30-60 min'
    WHEN booking_lead_min < 120 THEN '3 · 1-2 hr'
    WHEN booking_lead_min < 240 THEN '4 · 2-4 hr'
    ELSE '5 · 4 hr+'
  END AS booking_lead_bucket,
  COUNT(*)                       AS appointments,
  ROUND(AVG(is_noshow) * 100, 1) AS noshow_pct
FROM workspace.default.appointment_clean
WHERE is_telephone = 1 AND is_after_hours = 1
GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- TILE 5 · No-show by day of week (rebalance capacity midweek)
SELECT day_of_week, dow_num,
       COUNT(*)                       AS appointments,
       ROUND(AVG(is_noshow) * 100, 1) AS noshow_pct
FROM workspace.default.appointment_clean
WHERE is_telephone = 1 AND is_after_hours = 1
GROUP BY day_of_week, dow_num
ORDER BY dow_num;

-- COMMAND ----------

-- TILE 6 · Adoption & reliability trend by month
SELECT appt_month,
       ROUND(SUM(is_telephone * is_after_hours) * 100.0 / SUM(is_after_hours), 1)                    AS telephone_share_pct,
       ROUND(AVG(CASE WHEN is_telephone = 1 AND is_after_hours = 1 THEN is_noshow END) * 100, 1)     AS ah_tel_noshow_pct
FROM workspace.default.appointment_clean
GROUP BY appt_month ORDER BY appt_month;

-- COMMAND ----------

-- TILE 7 · Provider no-show distribution (coaching targets, >= 50 appts)
SELECT PROVIDER_ID,
       COUNT(*)                       AS appointments,
       ROUND(AVG(is_noshow) * 100, 1) AS noshow_pct
FROM workspace.default.appointment_clean
WHERE is_telephone = 1 AND is_after_hours = 1
GROUP BY PROVIDER_ID
HAVING COUNT(*) >= 50
ORDER BY noshow_pct DESC;
