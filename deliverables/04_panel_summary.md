# After-Hours Telephone Clinic — Findings for the Analytics Panel

**Data:** 125,053 appointments, one site (`SCH`) / one department (`MED`), 150 providers, 70,588 patients,
2009-12-01 → 2010-06-11 (~6.4 months). Source: Access `.mdb` → CSV, analyzed in Python (pandas) via the
cleaned `silver.load_clean()` layer. After-hours = scheduled time ≥ 17:30; telephone = `Telephone Visit`.

---

## The reframe
The after-hours clinic is not a scheduled telephone service — **it is a same-day, on-demand urgent-access
channel.** 100% of after-hours appointments are booked the same day, with a **median booking lead of ~56
minutes**. So I measured it the way MAPMG's Care-from-Home program is measured: as an access channel judged on
**cost avoidance and efficiency**, not on a generic "completed vs cancelled" frame (which the data can't support
— there is no cancellation, reschedule, duration, or diagnosis field).

## Q1 — Staffing: **3 physicians weekday evenings, 2 on weekends, +1 floating surge buffer**
Sized to *concurrent* demand, not daily totals. On a 10-minute slot grid one physician clears ~3 slots per
30-minute window. Peak completed load in a 30-min window is **6 at the median, 9 at the 95th percentile** →
ceil(9 ÷ 3) = **3 physicians** to keep midweek patients out of a queue; weekends run lighter (→ 2). Protect the
**18:00 peak hour**. Cross-checked against observed productivity (~7–8 completed calls per physician per evening).

## Q2 — Effectiveness: a well-adopted, low-cost access channel whose *clinical* value is unproven
Be precise about what the data can and can't establish — this is the credibility of the whole answer.

**What we can prove:**
| Dimension | Result | Benchmark |
|---|---|---|
| **Adoption (strongest claim)** | Telephone = **~60% of after-hours volume**, stable every month, booked same-day on demand | Revealed preference — patients consistently choose it |
| **Cost-efficiency** | ~3.8 completed calls / physician-hr | ~1.7× in-person (~2.2) → lower cost per contact in a capitated model (caveat: from slot spacing, not measured call length) |

**What we can NOT prove (and shouldn't claim):**
| Dimension | Finding | Why it's not a win |
|---|---|---|
| **Clinical resolution** | telephone → in-person within 3 days **16.7%** vs in-person → **7.7%** | Telephone routes ~2× more patients onward; completed vs no-show calls resolve *equally*. So we can show it's **not deferring** care, but **cannot** show it resolves — plausibly correct triage, but unmeasurable without diagnosis/ER linkage |
| **Reliability (the weakness)** | **19.4% no-show** (81% show) | ~2× in-person; wastes reserved capacity |

**Net:** a channel patients clearly want and that runs cheap — worth keeping — but its clinical effectiveness is unmeasured, so *support and instrument it, don't blindly expand.*

## Q3 — Recommendations (each backed by a query, not a platitude)
*Why cut no-shows?* Not to reduce in-person follow-ups (completed vs no-show calls follow up at the same
~17%, so it won't). The payoff is **recovered physician capacity and access** — a 19% no-show burns
reserved after-hours slots another patient could have used, which in a capitated system is wasted
clinician time.
1. **Confirm at booking, not 2 hours out.** No-show rises as booking gets last-minute: **25% for calls booked
   <30 min ahead vs 16% at 1–2 hr.** With a 56-min median lead, a 2-hour reminder is impossible — use an
   instant booking confirmation + short pre-call SMS aimed at the <60-min cohort.
2. **Rebalance capacity midweek.** No-show is **Thu 29% / Wed–Fri ~23% vs Sat–Sun ~7–8%.** Overbook the
   midweek evenings; trim quiet weekend capacity.
3. **Spread the top performers' playbook.** Provider no-show ranges **0% to 43%**, and the highest-*volume*
   provider has the *worst* rate — a coaching and booking-practice opportunity, not patient luck.
4. **Fill slots before adding staff.** Median session fill is **0.79** (~21% of in-session slots empty) on top
   of the 19% no-show — effective utilization is the lever, not headcount.

## What surprised me
The highest-volume after-hours physician runs a **43% no-show rate** while peers at similar volume sit near
zero — the biggest, most fixable efficiency lever in the dataset.

## Data I'd want next
**Encounter/diagnosis linkage and call duration** — to convert the 83% "resolution" proxy into a real clinical
outcome, and to calibrate slot length. Also patient acuity and a reason-for-no-contact field.

## Production path
`silver.load_clean()` is a single module that centralizes the date-parsing and business definitions; profiling,
analysis, and dashboard all import it, so the logic lives in exactly one place. The pipeline runs locally in
VSCode/Cursor today (pandas), and the same transformations map cleanly onto Spark/Databricks when MAPMG's
migration lands — the silver layer becomes a registered view and the pandas groupbys become SQL. The four
scripts (silver → profiling → analysis → dashboard) are the deployable pipeline.

---
### Methodology & data-quality notes
- **SHOW_CODE has 3 values** (`Y`/`N`/`P`), not 2; N and P both = no-show per the dictionary.
- **Export quirk handled centrally:** `*_DATE` columns carry a placeholder time, `*_TIME` columns a placeholder
  date (`12/30/99`) — parsed in the silver view so no downstream query mis-reads timestamps.
- **No cancellation/reschedule signal** exists — "effectiveness" is necessarily show/throughput/resolution-based.
- **Single site/dept, 6.4 months** — no cross-site or true-seasonality claims; trend is directional.
- 52 `Y` rows have a null check-in (flagged, retained). No-shows correctly have null check-in.
