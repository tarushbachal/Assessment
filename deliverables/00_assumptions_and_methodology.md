# Assumptions & Methodology — read this before the notebooks

This is the "why" behind every number. Anyone can write the pandas; what makes the analysis
defensible is knowing exactly what we assumed, what the data *can't* tell us, and where the answers
are biased. Each item below is written as **the fact → why it matters → how we handled it / how to
defend it in the panel.**

---

## 1. Dataset at a glance

- **Grain:** one row = one scheduled appointment. (Checked for duplicate rows — none.)
- **Size:** 125,053 appointments.
- **Scope:** a single facility (`FACILITY = SCH`) and a single department (`DEPARTMENT = MED`).
  Every row. So there is **no site-to-site or specialty comparison possible** — this is one
  same-day medicine clinic.
- **People:** 150 providers, 70,588 patients.
- **Time span:** 2009-12-01 → 2010-06-11, about **6.4 months**. December and June are partial
  months. → We **cannot claim seasonality**; any month-over-month trend is directional only.

---

## 2. Data quirks we had to fix (the "did the cleaning right" credibility points)

**a) The date and time columns are split with fake placeholders.**
The file came from an Access `.mdb` export. The `*_DATE` columns hold the real date but a fake time
(`00:00:00`); the `*_TIME` columns hold the real time but a fake date (`12/30/99`).
- *Why it matters:* if you naively run `pd.to_datetime(APPOINTMENT_TIME)`, **every appointment
  parses as 30 December 1999**, and your entire "after 17:30" filter and all weekday/month grouping
  is silently wrong — no error, just wrong answers.
- *How we handled it:* take the real half from each — date from `*_DATE` (first 8 chars), clock time
  from `*_TIME` (last 8 chars). Done once in `silver.py`.

**b) `SHOW_CODE` has THREE values, not two.**
The data dictionary writes "N/P" as if it's one label, but the column actually stores `Y` (111,820),
`N` (12,573), and `P` (660).
- *How we handled it:* `Y` = showed up (`is_completed`); **both `N` and `P` = no-show** (`is_noshow`),
  per the dictionary.

**c) There is NO cancellation, reschedule, call-duration, or diagnosis field.** *(Most important
structural fact in the whole assessment.)*
- *Why it matters:* the brief's generic "completion vs cancelled vs rescheduled" framing is
  **impossible** — those columns don't exist. We also can't measure how long a call took or what it
  was clinically about.
- *How we handled it:* this single fact forces the entire Q2 reframe (see §4).

**d) Check-in is unusable, so we deliberately ignored it.**
Check-in is null for *every* no-show (correct) and for 52 stray `Y` rows. More importantly, for
telephone visits the check-in time ≈ the scheduled time (median gap 0 min) — it's a **system stamp
written at the slot time, not a real "patient arrived" event.**
- *How we handled it:* excluded it. It can't serve as wait-time or handle-time. (If we ever wanted a
  punctuality/wait metric we'd revisit, but it isn't one of the three questions.)

---

## 3. Definitions we chose (and why)

| Term | Our definition | Note |
|---|---|---|
| **After-hours** | scheduled time **≥ 17:30** | Implemented as minutes-since-midnight (`appt_min_of_day ≥ 1050`), **not** the hour. So 17:15 (`appt_hour = 17`) is correctly **excluded** — using the hour would wrongly include it. |
| **Telephone** | `APPOINTMENT_TYPE == "Telephone Visit"` | Exact label; only two types exist (the other is `In-Person Visit`). |
| **Completed / no-show** | `Y` / (`N` or `P`) | See §2b. |
| **Booking lead (minutes)** | appt time − booking time, **same-day only** | Guarded by `lead_days`: if the appointment was booked on a different day, the minute-subtraction is meaningless, so we blank it out. Safe here because all after-hours appointments are same-day. |

---

## 4. The reframe: effectiveness = access channel, not "completed vs cancelled"

Because there is **no cancellation, duration, or diagnosis data** (§2c), we can't measure
effectiveness the generic way. Instead we measured it the way MAPMG's **Care-from-Home** program is
judged — as an **access channel** delivering cost avoidance and efficiency — across three things the
data *can* support:

- **Access / adoption** — is the channel meeting same-day demand and being used? *(provable — strongest claim)*
- **Cost-efficiency** — patients handled per physician-hour vs in-person. *(provable, but a cost claim, not a quality one; from slot spacing, not measured call length)*
- **Resolution** — does the call settle the issue rather than defer it? *(NOT provable — see §6d; telephone routes ~2× more patients to in-person than in-person does, and completed = no-show calls, so clinical effect is unmeasurable)*

…with **reliability (no-show rate, 19.4%)** as the one clear weakness.

**Calibrated verdict (say exactly this, no more):** a **well-adopted, low-cost access channel** whose
*reach* and *cost-efficiency* are demonstrable, but whose **clinical effectiveness is unproven with this
data**, plus a 19% no-show leak. So: *support and instrument it, don't blindly expand.* This honesty —
claiming only what the data supports and naming what it doesn't — is the differentiator, not the code.

We also discovered the channel is **same-day and on-demand**: 100% of after-hours appointments are
booked the same day, median lead ~56 minutes. It's an urgent-access valve, not a planned diary.

---

## 5. Assumptions in the staffing math (Q1)

- **10-minute slot grid — *verified from the data*, not given.** 99.6% of after-hours appointments
  sit exactly on a 10-minute mark, and the most common gap between back-to-back appointments for the
  same physician is exactly 10 minutes (bigger gaps are just empty slots). So the booking cadence is
  10 minutes.
- **"3 patients per 30-minute window" follows from the grid** (30 ÷ 10 = 3 slots one physician can
  cover).
- **We staff to the 95th-percentile *concurrent* window, not the daily average.** Averaging across an
  evening would understaff the busy bursts and leave patients queued; sizing to peak concurrency
  (then dividing by 3) protects the midweek 18:00 rush without paying for idle weekend capacity.
- **No-shows are excluded from demand** — you staff for patients who actually call.

---

## 6. Biases & limitations — the centerpiece *(this is what the panel will probe)*

**a) Circularity — the staffing answer replicates the past, it doesn't optimize it.**
The 10-minute grid reflects **how the clinic already chose to book**, not how long an after-hours
call truly needs. So "3 physicians" really means *"to reproduce the service level already delivered,
you need roughly the staffing already used."* It is a **demand-replication estimate, and a lower
bound — not an optimum.** Say this out loud to the panel; it's more credible than presenting 3 as
objective truth.

**b) Supply censors the demand we can see.**
We only observe appointments that *fit into the slots that were offered*. There are no abandoned
calls, no waitlist, no "couldn't get a slot," no patients who gave up and went to the ER. So the
busiest windows we measured are a **floor** on true demand, not the real peak.

**c) Handle time is assumed, not measured.**
The 10-minute grid is the **booking** cadence, not the **call length** (no duration field). If real
calls average 15 minutes, a physician clears 2 per 30 min, not 3 — and the true staffing need is
~50% higher. We genuinely cannot tell from this data.

**d) Every Q2 metric is observational too.**
- **No-show (19.4%)** is measured only on people who *got* a slot — hard-to-reach patients who never
  booked are invisible, so the real "miss" is understated.
- **Throughput (3.8/hr)** is partly an artifact of defining slots as 10 minutes — it's "patients per
  booked hour," not "per clinical need."
- **Resolution proxy (~83%)** is the weakest metric and easy to over-read. The no-show cohort — who got
  **no call at all** — has the *same* ~17% in-person follow-up as the completed cohort. So equal rates only
  prove the call isn't **deferring** care; they do **not** prove it **resolves** anything (the no-call group
  "resolves" equally). Non-follow-up may be self-resolution, care at an **outside ER we can't see**, or going
  without. Clinical effect is **unmeasurable** here without ER/encounter linkage.
  - *Knock-on for Q3:* because reducing no-shows won't change the 3-day in-person rate, the no-show
    recommendations are justified on **wasted-capacity + access** grounds (a no-show burns a reserved
    physician slot), **not** on cutting downstream in-person demand.

None of these are wrong — they're all true "given the system as it ran." Stating that boundary is the
point.

**e) One thing that *strengthens* the productivity & no-show claims: the within-physician control.**
A fair worry is "maybe telephone just looks faster because faster doctors do more of it." We ruled that
out by comparing each physician **against themselves**: among the 104 physicians who did both modes after
hours, **72% are faster on the phone** (3.8 vs 2.3 /hr). Same for no-show — the *same* physician runs
~11% telephone no-show in the daytime vs ~18% after hours. So the productivity gain and the after-hours
no-show gap are about the **modality and the setting**, not about which physicians happen to work evenings.
(Context: it's one shared pool — ~125 of 150 physicians work both day and evening, and almost all do both
telephone and in-person; nobody is a pure "after-hours phone specialist".)

**f) Supply-induced demand — staffing doesn't just *meet* demand, it *grows* it.**
Adding after-hours capacity makes slots easier to get → shorter waits → more patients book → demand
rises to fill the new supply. In healthcare this is **Roemer's Law** ("a built bed is a filled bed").
Consequences:
- Demand is **not a fixed target you staff against** — the staffing decision partly *creates* the
  demand, which is another face of the endogeneity in (a). A static peak-load count therefore
  *understates* what demand becomes once you expand.
- "Staff until nobody ever waits" is a **runaway loop** — you can always induce a little more
  low-acuity demand. This is exactly why an **explicit service-level target** (and **acuity data**)
  is needed: to tell whether the induced demand is unmet need worth serving (deflecting the ER) or
  low-value visits.
- *Panel-ready line:* "Demand here is endogenous to the staffing decision — expanding capacity
  induces demand (Roemer's Law), so the honest model is a feedback/equilibrium one settled with a
  capacity experiment, not a one-shot forecast against fixed demand."

---

## 6b. What kind of clinic is this? (characterizing `DEPARTMENT = MED`)

The department is labelled `MED` on every row, but we can characterize *what kind of practice it is*
from the in-person patterns — and everything points to **primary / general adult medicine (internal
or family medicine)**, not a procedural specialty:

| Signal | Value | What it implies |
|---|---|---|
| In-person slot grid | 88.7% on 10-min marks; **most common gap 20 min** | Standard ~20-minute office visits (double the 10-min phone slot) — classic primary-care visit length |
| Clinic hours | ~05:00 – 20:00 | Long outpatient day (early slots likely fasting labs) |
| Panel | 70,588 patients / 150 providers; **median 1 visit**, 59% single-visit in 6 months | Broad, low-frequency general population — not a specialty referral stream |
| Same-day after-hours telephone triage | exists at all | Primary-care / urgent-access behaviour; procedural specialties (surgery, radiology) don't run same-day phone visits |

So `MED` ≈ **Adult / Internal / Family Medicine** (consistent with Kaiser/MAPMG's primary-care model).
The 20-min in-person vs 10-min telephone split is itself a finding — it's part of why telephone
throughput runs ~1.7× in-person.

---

## 7. Key findings, each tied to its assumption

| Finding | Number | Rests on assumption |
|---|---|---|
| Staffing — weekday / weekend | 3 / 2 (+1 surge) | 10-min grid → 3-per-30-min; 95th-pct concurrency; no-shows excluded (§5, §6a) |
| Peak concurrent load (weekday) | 6 median, 9 at p95 | completed-only demand; 30-min window |
| After-hours telephone no-show | 19.4% (vs in-person ~10%) | N/P = no-show; observational on booked patients (§6d) |
| Productivity | 3.8 vs 2.2 per physician-hr | session span as proxy for hours; inflated by short slots (§6d) |
| Resolution proxy | ~83% no in-person within 3 days | in-clinic follow-ups only; temporal not clinical (§6d) |
| Adoption | telephone ~60% of after-hours, stable | directional only — 6.4 months (§1) |
| Booking-lead → no-show | <30 min ≈ 24% vs 1–2 hr ≈ 16% | same-day booking lead (§3) |
| Worst provider | 43% no-show at highest volume | ≥50-appointment filter for stability |

---

## 8. Data I'd want that I didn't have

| Wanted data | Which question it strengthens |
|---|---|
| **Call duration** | Q1 — replaces the assumed 10-min handle time; calibrates true staffing |
| **Abandoned / overflow call volume, wait-to-callback** | Q1 — exposes the suppressed demand the slots hide (§6b) |
| **Encounter / diagnosis linkage** | Q2 — turns the 83% timing proxy into a real clinical resolution outcome |
| **Patient acuity / demographics, reason codes** | Q2/Q3 — who no-shows and why; targets interventions |
| **Multiple sites, a full year** | All — cross-site comparison and real seasonality |

---

## 9. Likely panel questions + how to answer

- **"Walk us through the staffing question."** Lead with *method*: staff to peak concurrency, not
  averages; the 10-min grid is verified from the data; 95th percentile → 3 weekday / 2 weekend. Then
  the honest caveat: it's a replication estimate and a lower bound (§6a).
- **"What surprised you?"** The highest-*volume* after-hours physician runs a **43% no-show rate**
  while peers at similar volume sit near zero — the biggest, most fixable lever in the data.
- **"What data did you want that you didn't have?"** §8 — lead with call duration and
  encounter linkage.
- **"How would this scale in production?"** `silver.py` is one cleaning layer everything imports; the
  same transforms map onto Spark/Databricks (silver becomes a registered view, the groupbys become
  SQL) when MAPMG's migration lands.
- **"How effective is the channel?"** §4 — split it: **provable** = adoption (strong, ~60% stable) and
  cost-efficiency (~1.7× throughput); **unprovable** = clinical resolution (telephone routes ~2× more to
  in-person; no outcome data); **weakness** = 19% no-show. Land on: *well-adopted, low-cost channel worth
  keeping, but instrument it before expanding.* Don't overclaim "effective".

---

*Companion to `04_panel_summary.md` (the 1-page exec summary). This document is the deeper "why".*
