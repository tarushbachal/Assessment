# Databricks dashboard — build steps

Everything here is code and commits through your Git folder (`Workspace > Home > Assessment`).
Bronze table assumed at **`workspace.default.appointment_data`**. No Genie, no drag-drop analysis.

## Files
| File | What it is |
|---|---|
| `00_silver_view.sql` | Creates the `workspace.default.appointment_clean` view (SQL twin of `silver.py`). Run once. |
| `dashboard_queries.sql` | The 7 tile queries, to run/verify individually in the SQL editor. |
| `after_hours.lvdash.json` | The dashboard as code — datasets + widgets wired to the silver view. |

## Steps
1. **Start a SQL Warehouse** — Serverless, 2X-Small is plenty. (SQL editor / dashboards need a running warehouse.)
2. **Create the silver view** — open `00_silver_view.sql` as a notebook (or paste into the SQL editor) and run it. The sanity-check cell should return **125,053 rows, 4,383 after-hours telephone, 19.4% no-show**. If it doesn't, see *Troubleshooting* below.
3. **(Optional) verify tiles** — run each query in `dashboard_queries.sql` to confirm results before wiring the dashboard.
4. **Create the dashboard from the JSON** — two ways:
   - **Git-native:** the `.lvdash.json` in your synced repo folder appears in the workspace; open it and it renders as a dashboard. Pick the SQL Warehouse when prompted, then **Publish**.
   - **Import:** Dashboards → top-right **⋮ / Create** → **Import dashboard from file** → choose `after_hours.lvdash.json` → select the warehouse → **Publish**.
5. **Confirm no Genie** — do **not** create a Genie space on this data. The dashboard needs none. (Optional extra: a workspace admin can disable the Assistant/AI features in settings — a nice PHI-caution point to mention in the interview, even though the data is synthetic.)

## What the dashboard shows (the calibrated story)
- **KPIs:** after-hours telephone volume, telephone vs in-person no-show, telephone share of after-hours.
- **Demand heatmap** (day × hour) → drives the staffing peak.
- **Staffing table** → 3 weekday / 2 weekend physicians (min / recommended / peak).
- **No-show by booking lead** → the actionable Q3 driver (last-minute bookings fail most).
- **No-show by day** → rebalance midweek.
- **Adoption/no-show by month** → stable ~60% adoption.
- **Provider no-show** → 0–43% spread, coaching lever.

## Troubleshooting
- **Silver view returns 0 rows / null dates:** the bronze columns may already be typed as `TIMESTAMP`
  rather than `STRING`. The view already tries both formats via `try_to_timestamp`, so this should be
  handled — but if dates look wrong, run `DESCRIBE workspace.default.appointment_data;` and check the
  types of `APPOINTMENT_DATE` / `APPOINTMENT_TIME`, then tell me and I'll pin the parse format.
- **Dashboard import errors on a widget:** the `.lvdash.json` schema is version-sensitive and I couldn't
  test it against your workspace. The **datasets (SQL) are the durable part** — if a chart won't render,
  delete that one widget and re-add it in the UI (pick the dataset, choose the chart type, drop the field
  on the axis — ~2 clicks). All the analysis lives in the datasets, not the chart config.
- **`percentile` not found:** use `approx_percentile(peak, 0.95)` instead (older warehouses).
