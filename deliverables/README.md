# MAPMG After-Hours Telephone Clinic — Analysis Pipeline (Jupyter)

Jupyter-notebook pipeline answering the three assessment questions. Built with pandas, runs entirely in
**VSCode / Cursor** — open a notebook and **Run All**, no terminal or database required. The notebooks ship
with outputs already embedded, so they render with results on open.

## Setup
```bash
pip install pandas numpy jupyter
```
(VSCode/Cursor will prompt to install the Jupyter + Python extensions the first time you open an `.ipynb`.)

## How to run
Open a notebook and click **Run All** (or run cells top-to-bottom). Each notebook imports the shared
cleaning layer (`silver.py`), so the parsing logic is never repeated. Run notebooks from the
`deliverables/` folder (the default — the kernel's working directory is the notebook's folder).

## Files
| File | Purpose |
|---|---|
| `00_assumptions_and_methodology.md` | **Read first.** The "why" behind every number — assumptions, data quirks, biases, and panel Q&A prep. This is the part that wins the assessment. |
| `silver.py` | The cleaned "silver layer". `load_clean()` parses the split date/time fields, decodes SHOW_CODE (Y/N/P), and adds business flags (after-hours, telephone, completed, booking lead). **Imported by every notebook.** |
| `01_profiling.ipynb` | Schema, coverage, distributions, null/integrity checks, time-parse validation. |
| `02_analysis.ipynb` | Q1 staffing · Q2 effectiveness scorecard · Q3 recommendations, with markdown narrative between each step. |
| `03_dashboard_data.ipynb` | Builds the summary tables and writes one CSV each into `dashboard_out/` (drop into any BI tool / Excel / plot). |
| `04_panel_summary.md` | One-page narrative for the panel. |

## Working interactively
In a Jupyter cell or the Python REPL:
```python
from silver import load_clean
df = load_clean()                                          # cleaned DataFrame, 125,053 rows
after_hours_phone = df[df["is_telephone"] & df["is_after_hours"]]   # the group we focus on
after_hours_phone["is_noshow"].mean()                      # 0.194
```

**Effectiveness is framed as a Care-from-Home-style access-channel scorecard** — Access / Resolution /
Productivity, with no-show as the reliability drag — because the data has no cancellation, duration, or
clinical-outcome fields and because that is the lens MAPMG measures this program on.

## Headline answers (all reproduced by the notebooks)
- **Q1:** 3 physicians weekday evenings, 2 weekends, +1 surge buffer (sized to 95th-pct concurrent load; peak hour 18:00).
- **Q2:** A well-adopted, low-cost access channel — **provable**: ~62% stable adoption (patients prefer it) and ~1.7× in-person throughput (cost-efficient per contact). **Unprovable with this data**: clinical effectiveness (no diagnosis/duration/ER link; telephone routes ~2× more patients to in-person than in-person does). Plus a 19.4% no-show leak (~2× in-person) that wastes capacity.
- **Q3:** Confirm-at-booking (last-minute bookings no-show most), rebalance midweek capacity, spread top-performer practices, fill empty slots before adding staff.
