# LifeOS — Product Specification — Version 1

**Status:** Living product and engineering specification  
**Primary platform:** iPhone first (SwiftUI)  
**Version 1 strategy:** Local-first with SwiftData, stable UUIDs, JSON-ready records  
**Repository:** `github.com/sirishdittakavi/LifeOS`

> **Mastery takes years. LifeOS makes the honest daily actions that create mastery visible.**

---

## 0. Implementation Status

Update this table whenever the code changes.

| Area | Status | Notes |
|---|---:|---|
| Profile model | ✅ First version | Add/edit/switch/hide optional parent, child and individual profiles with fully separate data |
| Profile identity | ✅ First version | Editable name, optional compressed photo, colour and parent/self-managed access intent |
| Profile preferences | ✅ First version | kg/lb display plus daily nutrition targets |
| Area model | ✅ First version | Generic editable hierarchy, profile ownership, activity-plan targets, purpose, related areas and active state |
| Area templates | ✅ First version | Built-in School, sport, movement, nutrition, weight and recovery Areas include editable starter Tasks; locally saved Areas remain reusable |
| Goal and outcome model | ✅ First version | Goal, typed primary/supporting Result Measures, Area Contributions, dated Result Check-ins, target-date comparison and five editable starter Goal templates |
| Goal dashboard | ✅ First version | Separates result progress from Today/week/month supporting-plan adherence, evidence confidence and next action |
| Area navigation | ✅ First version | Areas → nested Area detail; list-row edit, custom/template creation and safe deactivation |
| Plain-language planning UX | ✅ First version | User-facing model is Areas with Tasks, plus a dedicated Goals tab for measurable outcomes and Result Check-ins |
| Activity model | ✅ First version | Manual/template/AI-approved source |
| Schedule rule | ✅ First version | Once, daily, selected weekdays, any count per day/week, exact minute intervals |
| Calendar item | ✅ First version | Every calendar entry originates from an Activity |
| Today timeline | ✅ First version | Real-data progress ring, daily signals, due Goal Result check-ins and chronological glass depth cards with accessible 44pt controls and haptics |
| First-run onboarding | ✅ V1 | Opens on Today, supports multi-select built-in and custom Areas, generates editable Goals, Tasks and schedules through the generic models |
| Glacier identity | ✅ V1 | Restrained adaptive glacier artwork in the app icon and a subtle progress watermark on Today; Tasks remain visually dominant |
| Mobile schedule | ✅ First version | Seven-day strip, focused daily agenda, graphical date jump and interactive action cards |
| Mark Done / Skip | ✅ First version | Status and actual timestamps retained |
| Add task manually | ✅ First version | Fast task + inline category creation, exact numeric targets, time, duration and flexible repeat |
| Daily nutrition log | ✅ First version | Barcode lookup, label-photo OCR, saved photos, manual editing, macros, water and daily totals |
| Body-weight log | ✅ First version | Canonical kg storage, kg/lb display, goal distance, raw scale data and transparent 7-entry trend |
| Sport training log | ✅ First version | Uses the user's Sport Area name; generic sessions, repetitions, duration × effort workload and soreness trend |
| Seed templates | ✅ First version | Neutral single-profile start; optional starter plans for any added adult or child |
| Timer session | ⬜ Next | Basic data model present; dedicated timer screen next |
| Multiple tracking fields | ⬜ Next | Activity supports primary unit in first code version |
| Goals and measurements | ✅ First version | Numeric, rating, milestone and written Result types; increase/decrease/range targets and scheduled/manual check-ins |
| Notifications | ✅ First version | Profile-labelled Action reminders, weekly plan review and scheduled Goal Result check-ins |
| JSON backup/restore | ✅ First version | Schema 2 full-family export/merge includes Goals, contributions, Result Measures, check-ins, photos and templates; schema 1 restore remains supported |
| Store migration safety | ✅ V1 baseline | Explicit VersionedSchema and migration plan; persistent-store failure is blocked behind Retry or an explicitly confirmed, visibly marked temporary session |
| App privacy manifest | ✅ V1 baseline | Declares app-private UserDefaults access with approved reason CA92.1; local-only records are not declared as collected off-device |
| Portable metric contract | ✅ First version | Versioned JSON event envelope maps Action Sessions, Goal Results, nutrition, weight and generic sport evidence for Android/integrations without storing derived progress |
| Automated regression tests | ✅ First version | Headless unit/component tests plus an iOS SwiftUI construction check; GitHub runs core tests and compiles both XCTest bundles on every change |
| Repository protocol | ⚠️ Partial | Planning service separated; full persistence abstraction next |
| Family sync and accounts | ❌ Deferred | Secure child invitations, permissions and multi-device sync require a cloud identity service |
| Paid household management | 📐 Designed | StoreKit entitlement plus server-authoritative household/member limits; implementation deferred |

---

## 1. The Core Idea, in Plain Language

LifeOS helps a person define a measurable Goal, prepare a realistic plan, record what actually happened, and learn whether repeated effort is associated with a better outcome.

The product is not centred on isolated activities or charts.

It is centred on an honest separation between **effort** and **outcome**.

```text
Measurable Goal and target
        ↓
Supporting Areas and their contribution
        ↓
Scheduled Tasks
        ↓
Today's calendar
        ↓
Done / skipped / rescheduled / unplanned
        ↓
Result Check-in when evidence is available
        ↓
Compare adherence, outcome trend and target pace
        ↓
Keep, adjust or replace the plan
```

Every screen should answer:

> **What should I do next to make meaningful progress?**

The Goals Dashboard answers whether measured outcomes are moving toward their targets. Today remains the execution surface. Area screens answer whether the supporting plan was followed; they do not claim that an Area itself improved.

---

## 2. Core Product Decisions

| # | Decision |
|---:|---|
| 1 | **The Today calendar is the primary product surface.** |
| 2 | **Every calendar item originates from an Activity.** No unclassified calendar-only event exists. |
| 3 | **Each profile owns a separate calendar.** Parents and children have separate Areas, Tasks, Goals, and history. |
| 4 | **Activities may be created manually, selected from templates, or suggested by AI—but AI/template suggestions require approval.** |
| 5 | **Area is mandatory for every Task.** Tags are optional and support later analysis. |
| 6 | **Planned and actual values are stored separately.** Historical plans are never overwritten by actual results. |
| 7 | **A one-time manual event still creates a one-time Activity plus a Calendar Item.** It may later be saved as reusable. |
| 8 | **Complete-day tracking is supported but not forced.** LifeOS must not become surveillance or require accounting for every minute. |
| 9 | **Daily and weekly schedules are generated from activity rules, then remain editable by the user.** |
| 10 | **Goal progress and Task adherence are separate values.** Completing Tasks is evidence of effort, not proof that an outcome improved. |

---

## 3. Author's Intent

LifeOS began from a personal goal: building professional mastery over years rather than chasing short bursts of productivity.

The same principle applies to a software engineer, athlete, student, parent, musician, or child:

- decide what good looks like,
- perform intentional actions,
- repeat them consistently,
- measure outcomes,
- reflect and adjust.

LifeOS is not designed to collect data.

It is designed to help people make better decisions.

If a feature does not help a person plan, execute, measure, learn, or improve, it does not belong.

---

## 4. Who It Is For

| Profile | Typical pre-populated activities |
|---|---|
| Parent / professional | Office work, commute, gym, meals, sleep, family time, software learning |
| Child / student | School, homework, reading, meals, sleep, outdoor play |
| Athlete | Batting, throwing, pitching/bowling, fielding, strength, recovery, nutrition |
| Individual | Health, learning, hobbies, routines, custom activities |

The engine is identical. The starter activities differ.

---

## 5. Core Domain Model

```text
Workspace / Family
  └── Profile
       ├── Areas
       │    ├── Sub-areas
       │    └── Tasks
       ├── Goals
       │    ├── Area Contributions
       │    ├── Primary Result Measure
       │    ├── Supporting Result Measures
       │    └── Dated Result Entries
       ├── Activity
       │    ├── Tags
       │    ├── Tracking definition
       │    └── Schedule rules
       ├── Calendar Item
       │    ├── Planned start/end
       │    ├── Actual start/end
       │    ├── Status
       │    └── Source
       ├── Session
       │    └── Actual values
       ├── Food Entry
       │    ├── Meal photo / barcode source
       │    └── Calories, macros, water, servings
       ├── Weight Entry
       │    └── Canonical kilograms; profile chooses kg or lb display
       ├── Sport Entry
       │    ├── Repetitions and duration
       │    └── Perceived effort and soreness
       └── Goal Progress / Insight
```

### Definitions

- **Profile** — the person whose life or progress is represented.
- **Area** — where work belongs, such as School, Nutrition, Baseball, Mobility, or Software Development. An Area is organisational context; it is not itself an outcome.
- **Goal** — the real-world change the person wants, such as increasing a score from 68% to 85%.
- **Area Contribution** — how one Area is expected to support a Goal, with an optional weekly Action plan. Goals and Areas are many-to-many.
- **Result Measure** — the typed definition of success: number, rating, milestone or written assessment, plus baseline, target, direction and check-in cadence.
- **Result Entry** — dated evidence supplied by the profile, parent, coach or an eventual import.
- **Task** — the user-facing reusable definition of what the person may do; stored as `Activity` in Version 1.
- **Schedule Rule** — when and how often the Activity should occur.
- **Calendar Item** — one planned or unplanned occurrence on a specific day.
- **Session** — what actually happened, including timing and measured values.
- **Tag** — optional detail used for filtering and future analysis.

The canonical relationship is:

```text
Goal → Area Contributions → Tasks → Result Check-ins → Comparison
```

Tasks inside a selected Area contribute by default. An advanced Task-level include/exclude override may be added later without changing this model.

No calendar item may exist without an Activity reference.

---

## 6. Activity Sources

An Activity has one of these sources:

| Source | Meaning |
|---|---|
| `manual` | Created directly by a person |
| `template` | Selected from a LifeOS starter template |
| `aiSuggestion` | Suggested by AI and explicitly approved |
| `imported` | Imported from a future external calendar or service |

The application must never silently add an AI-suggested Activity.

```text
Suggestion
   ↓
User reviews category, target, time, frequency, reminder
   ↓
User approves
   ↓
Activity is created
   ↓
Calendar items are generated
```

---

## 7. Profile Calendars Generated from Activities

Each profile has separate:

- Activities
- Schedule rules
- Calendar items
- Sessions
- Measurements
- Reports

Example parent schedule:

```text
07:00–08:00  Gym                 Health
09:00–17:00  Office Work         Career
18:30–19:15  Family Dinner       Family / Nutrition
20:00–20:45  Java Practice       Software Development
```

Example child schedule:

```text
09:00–15:30  School              Education
17:00–17:45  Homework            Education
18:00–19:00  Hitting Practice    Baseball
20:00–20:30  Reading             Learning
```

A parent may manage a child profile without mixing the child's calendar with the parent's own calendar.

---

## 8. Schedule Rules

Version 1 supports:

- Once
- Every day
- Selected weekdays
- Any number of times per day, with an exact interval in minutes
- Any number of times per week, distributed across user-selected preferred days

An Activity may define:

- planned start time,
- estimated duration,
- target value,
- target unit,
- preferred weekdays,
- occurrences per day or week,
- exact interval between same-day occurrences,
- start date,
- optional end date,
- reminder time in a later iteration.

Future scheduling may add:

- flexible weekly quantity,
- exception dates,
- automatic distribution across available days.

### Weekly distribution example

```text
Batting goal: 500 swings/week

Mon 100
Tue 100
Wed Rest
Thu 100
Fri 100
Sat 100
Sun Rest
```

LifeOS may suggest this distribution, but the user owns the final plan.

---

## 9. Daily Calendar and Timeline

The Today screen displays Calendar Items in chronological order.

Each item supports:

- Start
- Mark Done
- Skip
- Reschedule (next iteration)
- Edit
- Record actual result
- Add an unplanned Activity

Statuses:

- Planned
- In Progress
- Done
- Skipped
- Rescheduled
- Unplanned

Example:

```text
TODAY — SIRISH

07:00–08:00  Gym
Health · Done · 48 actual minutes

09:00–17:00  Office Work
Career · In Progress

18:00–19:00  Hitting Practice
Baseball · Planned

20:00–20:45  Java Practice
Software Development · Planned

[ Add What Happened ]
```

LifeOS may show empty time blocks, but it must not force the user to fill every gap.

---

## 10. Planned vs Actual

Both must be preserved.

```text
Planned
18:00–19:00 Hitting Practice

Actual
18:12–18:48
80 swings
65 quality contacts

Status
Done
```

Required properties:

- planned start,
- planned end,
- actual start,
- actual end,
- status,
- category,
- tags,
- source,
- optional note.

This distinction supports later questions such as:

- Which categories consume the most time?
- How often does planned study actually happen?
- Which activities are frequently skipped?
- Does additional hitting practice align with bat-speed improvement?
- How much office work replaces sleep or family time?

LifeOS must describe correlation carefully and never claim causation without evidence.

---

## 10a. Daily Progress Tracking vs Actual (Aggregate View)

Section 10 preserves planned-vs-actual **per calendar item**. This section adds a **daily rollup** that answers, at a glance, *"How much of what I actually meant to do today, did I actually do — in real numbers, not just checkmarks?"*

Two different questions, both needed, both shown, never merged into one misleading number:

1. **Completion (already in the Today mockup, Section 12):** *"4 done · 1 skipped · 2 remaining"* — counts calendar items by status. Good for "am I moving through today's plan."
2. **Quantitative progress (new in this section):** for every Activity that has a `targetValue`/`targetUnit`, how much was actually logged today against that target — e.g. *80/100 swings*, *36/45 min Java Practice*, *0/150g protein*. Good for "is today's *effort* actually enough," which a checkmark alone can't tell you — a 5-minute "Done" Java Practice session and a 45-minute one both show as one green check under Section 10's status model.

```text
TODAY'S PROGRESS — SIRISH

Hitting Practice        80 / 100 swings         80%
Java Practice            36 / 45 min             80%
Protein Intake            0 / 150 g                0%
Sleep                    —  (no target set)         —

Overall today: 3 of 4 tracked targets have logged progress
```

**Rules:**
- An activity with no `targetValue` simply doesn't appear in this view — it's tracked by completion status only (Section 10), not penalized for lacking a number.
- Progress is **capped at 100% for any score/color coding**, but the real number (e.g. "120/100 swings") is always shown, never hidden — same non-negotiable rule as the old Daily Momentum guardrail.
- This view reads directly from `Session.values` rolled up by `activityId` for the day — it does not require a calendar item to be marked "Done" first. A person can log 80 swings against Hitting Practice while that calendar item still shows "In Progress," and this view reflects it immediately.
- A 7-day version of this same view (planned target vs. actual, per activity, per day) is the natural home for Weekly Review—as a trend, not a separate scoring system.

This section does not introduce a single blended "Momentum score." Completion tracking and number tracking remain two honest, separate views.

---

## 11. Manual and Unplanned Entries

When a user performs something unusual:

```text
Add What Happened

Park Play
16:15–17:05
Category: Health
Tags: Outdoor, Active, Family
```

LifeOS asks:

```text
Add once
or
Save as reusable Activity
```

Both choices preserve the core rule:

```text
Activity → Calendar Item → Session
```

A one-time entry creates a one-time Activity rather than an unstructured event.

---

## 12. Today Screen — Priority Mockup

```text
┌────────────────────────────────────────┐
│ Sirish                     Thu 6 Aug   │
│ [ Switch Profile ]                     │
├────────────────────────────────────────┤
│ TODAY'S PLAN                     67%   │
│ 4 done · 1 skipped · 2 remaining      │
├────────────────────────────────────────┤
│ 07:00  Gym                             │
│         Health · Done                  │
│         48 actual min                  │
│                                        │
│ 09:00  Office Work                     │
│         Career · In Progress           │
│         [ Finish ]                     │
│                                        │
│ 18:00  Hitting Practice                │
│         Baseball · Planned             │
│         [ Start ] [ Done ] [ Skip ]    │
│                                        │
│ 20:00  Java Practice                   │
│         Software Development · Planned │
│         45 min                         │
├────────────────────────────────────────┤
│ [ + Add What Happened ]                │
└────────────────────────────────────────┘
```

The first screen should feel like a useful daily calendar, not a statistics dashboard. Its progress hero must use the real planned-action completion summary; it must never show invented points, sample records or a hard-coded percentage. Daily signals remain supporting context below that honest plan summary.

The visual system uses restrained adaptive material, category-tinted depth and semantic status badges. All interactive controls provide at least a 44 × 44pt hit region, support Dynamic Type and VoiceOver labels/hints, preserve contrast in light and dark appearances, respect Reduce Motion, and use subtle selection feedback for direct actions. Decorative glass effects must never reduce legibility or become more prominent than the schedule.

---

## 13. Data Contract Examples

### Activity

```json
{
  "id": "uuid",
  "profileId": "uuid",
  "categoryId": "uuid",
  "name": "Java Practice",
  "source": "manual",
  "tags": ["java", "learning", "interview"],
  "targetValue": 45,
  "targetUnit": "minutes",
  "schedule": {
    "repeatType": "selectedWeekdays",
    "weekdays": [2, 3, 4, 5, 6],
    "plannedStartMinutes": 1200,
    "estimatedDurationMinutes": 45
  },
  "active": true,
  "createdAt": "2026-08-06T10:00:00+10:00",
  "updatedAt": "2026-08-06T10:00:00+10:00",
  "schemaVersion": 1
}
```

### Calendar Item

```json
{
  "id": "uuid",
  "profileId": "uuid",
  "activityId": "uuid",
  "date": "2026-08-06",
  "plannedStart": "2026-08-06T20:00:00+10:00",
  "plannedEnd": "2026-08-06T20:45:00+10:00",
  "actualStart": null,
  "actualEnd": null,
  "status": "planned",
  "source": "schedule",
  "createdAt": "2026-08-06T00:01:00+10:00",
  "updatedAt": "2026-08-06T00:01:00+10:00",
  "schemaVersion": 1
}
```

### Session

```json
{
  "id": "uuid",
  "profileId": "uuid",
  "activityId": "uuid",
  "calendarItemId": "uuid",
  "startedAt": "2026-08-06T20:03:00+10:00",
  "endedAt": "2026-08-06T20:43:00+10:00",
  "actualActiveSeconds": 2160,
  "values": {
    "minutes": 36,
    "notes": "Java concurrency practice"
  },
  "createdAt": "2026-08-06T20:44:00+10:00",
  "updatedAt": "2026-08-06T20:44:00+10:00",
  "schemaVersion": 1
}
```

---

## 14. Architecture

```text
SwiftUI Views
      ↓
View Models / Use Cases
      ↓
Planning Service + Progress Engine
      ↓
Repository Protocol                    [next refactor]
      ↓
SwiftData Repository
      ├── Full-family JSON Backup / Restore
      └── Portable Metric JSON         [Android, analytics, integrations]
```

Rules:

- Views must not calculate scheduling rules.
- Schedule generation belongs in `PlanningService`.
- Historical calendar items must not be regenerated destructively.
- Planned values and actual values are separate.
- A Calendar Item always references an Activity.
- New categories and activities are configuration, not new screens.
- Business logic must be unit-testable.
- JSON schemas are versioned.

### 14.1 Portable metric contract

SwiftData remains the iPhone persistence model because typed relationships protect Profile isolation and the Goal → Area → Action → Result graph. A second, Foundation-only contract exposes dated evidence without depending on SwiftData or SwiftUI:

```text
PortableMetricEnvelope (schema version + export date)
  └── PortableMetric
       ├── stable event ID and Profile ID
       ├── optional Area, Goal and definition IDs
       ├── event kind and occurrence date
       ├── title and note
       └── JSON-native typed fields
```

Version 1 event kinds are `action_session`, `goal_result`, `nutrition`, `weight` and `sport`. Flexible fields may contain strings, finite numbers, integers, booleans, arrays, objects or null. They use an explicit `{ type, value }` representation so a whole-number measurement is not silently decoded as an integer, and they must not reduce all values to strings. Canonical dates use ISO-8601 and canonical body weight uses kilograms.

The contract deliberately does **not** persist `progress`, status or confidence. Those values are derived from raw evidence, targets and the current Progress Engine so an algorithm update cannot leave stale values in storage. Every exported metric requires a Profile ID, duplicate event IDs are rejected, unknown future schema versions fail safely, and deterministic JSON round-trip tests protect the contract.

This event envelope is suitable for Android ingestion, analytics and future API boundaries. It does not replace the full-family backup, which also preserves Profiles, relationships, schedules, templates and photos. An Android client should implement equivalent typed domain entities with Room (or another local store), then map its evidence records to the same JSON contract; it should not attempt to run Swift protocols.

---

## 15. First Coding Iteration Scope

Included in the accompanying code:

- SwiftData models
- Profiles
- Categories
- Activities
- Schedule rules
- Calendar items
- Sessions
- Parent and child starter activities
- Today timeline
- Profile switching
- Add Activity
- Once/daily/weekday recurrence plus arbitrary daily/weekly counts and exact minute intervals
- Mark Done
- Skip
- Start basic activity
- Planned-vs-actual timestamps
- Daily Progress view (Section 10a): target vs. actual per tracked Activity, today
- Food logging by manual entry, barcode lookup, or nutrition-label photo
- Saved food photos, serving quantities, daily nutrition targets and progress
- Weight logging in kg or lb with canonical kg storage, goal distance and 7-entry trend
- Generic sport session logging with repetitions, workload, effort and soreness
- Cross-domain Today signals for protein, latest weight and sport minutes
- Profile-owned improvement pillars and categories
- Connected categories such as Mobility → Baseball and Nutrition → Body Development
- Editable category weekly session and minute commitments
- Template or custom category setup with explicit user approval
- Goal Dashboard with Today, Week and Month supporting-effort comparison
- Goal, Area Contribution, primary/supporting Result Measure and dated Result Entry
- Visible editable Goal templates for school results, sport performance, energy/recovery, personal weight range and project milestones
- Numeric, rating, milestone and written result capture with scheduled check-ins
- Increase, decrease, target-range and maintain-range result evaluation
- Separate Goal result progress, Area plan adherence and High/Medium/Low evidence confidence
- Area detail with purpose, Action schedule, related Areas and specialist tracking
- Local Action reminders, weekly Area-plan review reminders and Goal Result check-ins

Not yet included:

- Advanced statistical correlation and automatic causal inference
- Goal editing, archiving and Action-level contribution overrides
- Automatic imports for school scores, coaching systems and additional biometrics
- Full timer screen
- Multiple custom tracking fields
- Additional custom biometrics beyond weight
- Weekly planning distribution
- Portable metric import UI and external integrations
- Face ID/PIN
- Cloud sync
- AI API

---

## 16. Next Iteration

Priority order:

1. Goal editing, archiving, contribution wording and optional Action inclusion overrides
2. Additional specialist Goal templates with age-appropriate review guidance
3. Repeat foods, recipes, food search, and meal copy/paste
4. Apple Health weight/height import and connected-scale interoperability
5. Daily readiness check-in: sleep, energy, soreness, stress and notes
6. Baseball assessments, drill templates, video attachments and structured game stats
7. Weekly review connecting planned work, completed work and measured outcomes
8. Weekly planner, authentication and permissions

---

## 17. ADR Additions

- **ADR-010:** Today calendar is the primary product experience.
- **ADR-011:** Every Calendar Item originates from an Activity.
- **ADR-012:** Each Profile owns a separate calendar.
- **ADR-013:** Planned and actual values are immutable separate facts.
- **ADR-014:** Template and AI Activities require user approval.
- **ADR-015:** Complete-day tracking is optional, not mandatory.
- **ADR-016:** Category is mandatory; tags are optional.
- **ADR-017:** One-time manual entries create one-time Activities.
- **ADR-018:** The Dashboard is the confidence surface; Today is the execution surface.
- **ADR-019:** Categories are profile-owned improvement areas, not global labels.
- **ADR-020:** Categories may be related, but a Session is stored once and never duplicated for every benefit.
- **ADR-021:** Status and confidence are separate. Missing evidence must never appear as confident success.
- **ADR-022:** Templates require review and approval before they create tasks or reminders.

---

## 18. Design Review Checklist

Before adding a scheduling or calendar feature:

- Does it begin with an Activity?
- Is the Activity associated with exactly one Profile?
- Is Category present?
- Are planned and actual values preserved separately?
- Can the user edit or reject generated plans?
- Does it work offline?
- Does it avoid forcing total surveillance of the day?
- Can the data later be exported and analysed?
- Is scheduling logic outside the SwiftUI view?
- Can a parent and child maintain separate calendars?

---

## 19. Positioning: Not a Kanban Board

Fair question, worth answering directly since Section 9's statuses (Planned, In Progress, Done, Skipped, Rescheduled, Unplanned) do borrow vocabulary from Agile/Kanban workflows.

**What's genuinely similar:** the status model *reads* like a lightweight Kanban board — Planned/In Progress/Done maps loosely to a To Do / Doing / Done column set, and Section 10's planned-vs-actual instinct is the same honesty Agile teams get from sprint planning vs. sprint actuals (a burndown chart, in spirit). "Personal Kanban" is itself an established methodology — individuals applying Kanban's visualize-your-work principle to solo life management, not just software teams.

**What's structurally different, and matters more:**
- **Kanban is columns and cards; LifeOS is a clock.** Every Kanban tool — Trello, Jira Kanban, Flowlu, MeisterTask — organizes work as cards moved between static status columns, with no inherent time axis. LifeOS's Today screen (Section 12) is fundamentally a **chronological timeline** — 07:00, 09:00, 18:00 — not a board. There's no "column" a Hitting Practice card sits in; there's a *time* it's scheduled for.
- **No WIP limits.** Limiting work-in-progress is close to the defining discipline of real Kanban. LifeOS has no concept of "you may only have 3 things In Progress at once" — nor should it; a person's day isn't a pull-based production queue.
- **Recurring schedule rules are core, not bolted on.** Kanban cards don't natively recur daily/weekly with a target quantity (500 swings/week distributed across days, Section 8). This is closer to a habit tracker or a calendar app's recurring-event engine than to card-based work tracking.
- **Quantitative targets, not just task completion.** Section 10a's "80/100 swings" has no real Kanban equivalent — Kanban cards are binary-ish (in a status or not); they don't carry a target/actual number the way an Activity does here.

**Conclusion:** LifeOS looks Kanban-*adjacent* only in its status labels. Structurally it's a **personal daily planner with quantitative habit tracking**, closer in spirit to a calendar app crossed with a fitness/habit tracker than to Trello or Jira. If this comparison comes up with users, "it's your day as a timeline, not your tasks as a board" is the accurate one-line distinction.

---

## 20. Competitive Benchmark and Product Direction (August 2026)

This benchmark exists to guide product decisions, not to produce a checklist clone.

| Product | What it does exceptionally well | What LifeOS should learn | What LifeOS should not copy blindly |
|---|---|---|---|
| [MyFitnessPal](https://www.myfitnesspal.com/?macro-selector=true) | Large food database; barcode, meal-photo and voice logging; calorie/macro goals | Logging must be fast, correctable and available through several input methods | Competing on database size before the core athlete loop works |
| [Cronometer](https://cronometer.com/gold/) | Deep nutrient coverage, custom targets/biometrics, repeat foods and correlations | Add verified micronutrients, repeat meals and useful correlations in stages | Showing dozens of nutrients without explaining what action to take |
| [MacroFactor](https://help.macrofactorapp.com/dashboard/weight_trend) | Separates noisy scale readings from a smoothed weight trend; adapts energy guidance from logged intake and trend weight | Preserve raw facts and derived trends separately; weekly feedback beats reacting to one weigh-in | Opaque coaching or automatic target changes without user/parent approval |
| [GameChanger](https://gc.com/baseball) | Game scorekeeping, video, team operations, 150+ game/season statistics and spray charts | Structured game facts and season context matter | Rebuilding a full team scorekeeper before individual development is excellent |
| [Driveline TRAQ](https://help.drivelinebaseball.com/portal/en/kb/articles/what-is-traq) | Planned workouts, goals, assessments, video, device data and coach/athlete workflow | Development requires planned work, athlete feedback, workload and longitudinal assessment | Assuming every family owns specialist sensors or has a professional coach |

### Strategic position

LifeOS will not initially beat nutrition leaders at food-database breadth, GameChanger at live scoring, or TRAQ at specialist hardware integrations. It can build a more useful loop for an individual athlete or family:

```text
Today's plan
    + nutrition against personal targets
    + body trend in the person's preferred unit
    + sport work, effort and soreness
        ↓
One honest weekly review
        ↓
User / parent / coach approves next week's adjustment
```

The wedge is **cross-domain cause-and-context**, not more isolated charts. A baseball athlete should be able to see that throwing workload rose, soreness rose, sleep or nutrition logging was incomplete, and performance changed—without the app claiming that correlation proves causation.

### Product principles

1. **Canonical storage, local display.** Weight is stored in kilograms and displayed as kg or lb per profile. Conversions never mutate historical facts.
2. **Raw facts and derived insights remain separate.** Scale weight is retained; the current transparent trend is a 7-entry moving average. Future algorithms must be versioned and explained.
3. **Goals belong to a Profile, not an Area.** A Goal may have several Result Measures and several supporting Area Contributions. Weekly Area values describe plan adherence only.
4. **Targets are editable, not medical prescriptions.** Youth nutrition, weight and workload goals require parent/coach judgment. The product must avoid shame, punitive colors and automatic restriction.
5. **Workload needs context.** Sport load begins as duration × perceived effort, shown alongside repetitions and soreness. It is a conversation aid, not an injury predictor.
6. **Fast capture, mandatory review.** Barcode and photo-derived nutrition must remain editable and show their source and serving basis.
7. **Approval before adaptation.** Future weekly coaching may recommend changes, but never silently changes a person's targets or schedule.

### Roadmap gates

**Foundation — implemented:** profile-specific kg/lb, targets, barcode/label/manual food capture, serving quantities, body trend, generic sport workload and Today cross-domain signals.

**Logging depth:** repeat foods and meals, recipes, search, micronutrients, body measurements, readiness check-in, baseball drill templates, assessment metrics and video.

**Interoperability:** Apple Health, connected scales, structured imports from scoring/training systems, JSON backup and user-controlled export.

**Learning:** weekly summaries, data-completeness indicators, transparent correlations, coach/parent comments and approval-based recommendations.

**Advanced athlete development:** seasonal plans, throwing progressions, game-vs-training analysis, sensor integrations and role-based coach access. These are later gates, not reasons to weaken the daily loop now.

---

## 21. Goals, Results and Supporting Area Plans

### 21.1 Outcome architecture

LifeOS does not equate task completion with improvement. It stores the desired result, supporting effort and observed evidence separately:

```text
Profile
├── Areas and Focus Areas                       where work belongs
│   └── Actions                                 what the person does
└── Goal                                        what should change
    ├── Primary Result Measure                  decisive evidence
    ├── 0–2 Supporting Result Measures          interim evidence
    ├── Area Contributions                      how each Area supports it
    └── Result Entries                          dated observations
```

A Goal may be supported by several Areas, and one Area may support several Goals. The Goal–Area connection is a first-class `GoalAreaContribution` with a plain-language statement and weekly effort targets. Actions inside the selected Area and its descendants contribute automatically.

Example:

```text
Goal: Increase throwing velocity from 62 to 70 mph
├── Baseball contribution: mechanics practice 3× weekly
├── Strength contribution: power work 2× weekly
├── Mobility contribution: shoulder/hip routine 5× weekly
└── Primary Result: monthly measured throwing velocity
```

Areas remain grouped by editable pillars:

- Physical Development
- Sport Development
- Health & Nutrition
- Learning & Career
- Life & Relationships

Goals, Result Measures, Result Entries and Areas are owned by the selected Profile. Switching Profiles never blends evidence.

Relationships are not inheritance and do not duplicate facts. A Sprint Technique Session may have Speed as its primary category while Speed is shown as supporting Baseball. The Session is counted once; the relationship explains context.

### 21.2 Goal creation and typed Result Measures

The Goal wizard asks natural questions rather than exposing storage types:

```text
What result do you want?
How will you measure it?
What is the baseline and target?
Which Areas support it?
When is the next result available?
```

Supported Result types:

- **Number** — percentage, kg/lb, mph, seconds, count or another unit.
- **Rating** — a bounded ordered scale; stored numerically while displaying human labels.
- **Milestone** — incomplete/complete.
- **Written assessment** — evidence timeline only; it never becomes a fabricated number.

Numeric Results support `increase`, `decrease`, `reach a range`, and `stay in a range`. A Goal has one primary Result and may add supporting Results with independent schedules. For example, Mathematics can use a monthly mock-test Result and a quarterly school-exam Result.

Target validation is directional: an `increase` target must be above its baseline and a `decrease` target must be below it. Ratings remain inside their defined scale, and a target range requires its maximum to be greater than its minimum. Invalid or imported legacy configurations never produce a green Goal state.

A Result is evidence only after the user supplies a valid typed value. An untouched number field, blank written assessment or unselected milestone cannot be saved and never advances the check-in schedule. A deliberately entered numeric zero or explicit `Not completed` milestone remains valid evidence.

### 21.3 Dashboard periods

The Goals Dashboard offers:

```text
Today | Week | Month
```

The period controls the **supporting effort window** only. Result history remains dated and is not reset by the selected period. Today/Week/Month shows how many supporting Actions were planned and completed during that window, aligned with the latest Outcome observations.

The Dashboard never adds unrelated units together and never substitutes Action adherence for Result progress.

### 21.4 Goal status calculation

Each Goal has one result status:

- **Goal reached** — the latest primary Result meets the target or target range.
- **On track** — measured progress is close to or ahead of the expected target-date pace.
- **Needs review** — sufficient evidence exists but the Result is not moving at the expected pace.
- **Awaiting result** — no primary Result has been entered; completed Actions cannot fill this gap.
- **Too early to judge** — a baseline or first observation exists but there is not enough repeated evidence.

For an increasing numeric Result:

```text
result progress = (latest − baseline) ÷ (target − baseline)
```

Decreasing Results reverse the direction. Range Results compare distance to the nearest target boundary. Values are clamped for display, while raw observations are never overwritten.

### 21.5 Evidence confidence

Confidence describes Outcome evidence quality, not motivation, character, diagnosis or causation:

- **High confidence** — at least three dated observations support a visible trend.
- **Medium confidence** — a baseline and/or one current observation exists.
- **Low confidence** — no usable Result observation exists.

Plan adherence is displayed separately. Missing check-ins are never treated as zero, and a green Action ring cannot make an Outcome green.

### 21.6 Dashboard and Goal detail presentation

Every Goal card shows:

- Latest primary Result and unit
- Progress from baseline toward the target
- Goal status and evidence confidence
- Supporting-plan adherence for Today/Week/Month
- One honest next action

The Goal detail keeps two charts visually separate but aligned in time:

1. **Outcome trend** — dated Result points plus target line/range.
2. **Effort** — completed versus planned Actions for every supporting Area.

Selecting a Result explains what happened between observations, such as: `13 study hours · 91% of planned Actions · score 74% → 79%`. The app may say the plan is associated with improvement; it must not claim that one Area caused the result.

### 21.7 Reminder policy

Reminders require explicit approval. Action reminders and Result check-ins are different:

- Daily and selected-weekday activities use their planned start time.
- Multiple-times-per-day activities notify at every occurrence that fits before midnight.
- Times-per-week activities divide the requested count across preferred days; if a day receives multiple occurrences, the exact minute interval is used.
- One-time activities notify only if their fire date is still in the future.
- An enabled category receives a Sunday weekly-review reminder.
- Every notification identifies the Profile and Area so a parent managing multiple people can tell who the reminder belongs to.
- Adding an Action inside a reminder-enabled Area or Focus Area refreshes its notifications immediately; saving the Area again is never required.
- Disabling reminders removes pending requests for the category and its activities.
- A Result Measure may be weekly, monthly, every three months or entered whenever available.
- Scheduled Result reminders identify the Profile, Goal and Result Measure. Due check-ins also appear on Today with a direct result-entry action.
- Saving a Result advances its next check-in according to that measure's cadence and refreshes the reminder.
- An overdue or missing Result is shown as `Awaiting result`; it is never recorded as zero.
- Notification denial never blocks local planning or tracking.

Dynamic catch-up notification timing is a later milestone because it requires reliable background progress evaluation. The current dashboard still provides the exact catch-up action whenever opened.

### 21.8 Safety and honesty

- Do not require every category every day; cadence belongs to the approved plan.
- Do not shame a child for weight, nutrition, soreness or missed work.
- Do not call workload an injury predictor.
- Do not infer causation from connected categories.
- Do not judge a Goal from Action completion when Outcome evidence is missing.
- Do not convert written assessments into numeric charts.
- For children, weight/height trends are observations with parent/clinician-set targets, not automatic diet prescriptions.
- Do not hide incomplete logging behind a green ring.
- Do not duplicate one Session across related categories.

---

## 22. Flexible Task Recurrence and Fast Creation

The creation flow uses the user's language: **Add an Action** and **Add an Area**. An Action cannot be saved without an Area because the Area explains where that work belongs and which Goals it may support. A new Area can be created inline without leaving the Action form.

### 22.1 Exact input, not fixed jumps

Target quantity, duration, repeat count, and interval are direct numeric fields. Minus and plus buttons change the number by one, but typing is always available. The UI must never force five-minute or five-repetition jumps.

Examples:

```text
High knees: 4 times/day, first at 06:30, every 17 minutes
Mobility break: 8 times/day, every 45 minutes
Batting practice: 3 times/week on Mon, Wed and Sat
Throwing care: 9 times/week across Mon, Wed and Fri, 20 minutes apart when repeated on one day
```

### 22.2 Occurrence generation

For multiple times per day:

```text
occurrence n = first start + (n × interval minutes)
```

Only occurrences whose start time is before midnight belong to that day. The form blocks Save when the requested count and interval would run past midnight and explains how to correct the schedule; it never silently creates fewer occurrences than requested.

For times per week, the requested count is divided as evenly as possible across the selected preferred weekdays. Earlier selected days receive any remainder. When the weekly count exceeds the number of preferred days, the additional same-day occurrences use the exact interval.

Each occurrence becomes its own Calendar Item. Its stable uniqueness rule is:

```text
Activity ID + calendar date + planned start time
```

This prevents duplicate generation while allowing the second, third, or fourth occurrence to exist independently. Each occurrence can therefore be completed, skipped, or rescheduled separately.

### 22.3 One schedule engine

`PlanningService.scheduledStartMinutes` is the single schedule calculation used by:

- Today timeline generation
- Daily/weekly/monthly Area-plan adherence
- Due-task and evidence-confidence counts
- Local notification timing

The UI must not implement a second version of recurrence math. This keeps the dashboard honest: four planned repetitions count as four opportunities, not one activity label.

### 22.4 Guardrails

- Counts and intervals are positive whole numbers.
- Duration may be any positive whole minute, not only multiples of five.
- A selected-weekday task requires at least one day.
- The calendar remains the authoritative visible list when device notification limits prevent every high-frequency reminder from being pending simultaneously.
- Existing calendar history is never destructively rewritten after a task rule changes.

---

## 23. Generic Area Hierarchy

The schedule example that motivated this decision contains coloured labels such as Athletics, Driveline, Defensive/Aaron, Academics and Leisure. Those labels are **examples of grouping**, not product-defined domains. LifeOS must not assume that every person plays baseball, attends school, uses a named training provider, or defines leisure as entertainment.

The generic structure is:

```text
Improvement Area
  └── Subcategory / Program (optional, nestable)
        └── Task / Habit
              └── Calendar occurrences
```

Illustrative mappings only:

```text
Baseball → Driveline → Pitching drill
School → Academics → Homework
Entertainment → Leisure → Gaming

Health → Cardio → Running
Career → Certification → Study chapter
Music → Piano → Scales practice
```

Every label is created and editable by the user. Templates may suggest names, but must never lock vocabulary or hierarchy.

### 23.1 Containment versus relationship

Containment answers **"what broader area is this part of?"** A program has at most one parent.

Relationship answers **"what other area is relevant?"** An Area may relate to many Areas. Goal contribution is separate and explicitly answers **"how does this Area support this Goal?"**

For example, Driveline may be contained by Baseball, while Mobility is a separate improvement area related to Baseball. Moving Mobility under Baseball would be a user choice, not an inferred rule.

### 23.2 Editing rules

- An Area can be top-level or placed inside any Area owned by the same Profile.
- Nesting may continue beyond one level when useful.
- An Area can be moved later without rewriting Action or calendar history.
- The Area itself cannot be selected as its parent.
- Descendants cannot be selected as parents; cycles are invalid.
- Deactivating a parent does not silently delete its children or tasks.
- Breadcrumbs show the full path when choosing a category for a task.
- An Area's name, parent placement, pillar, icon, colour, purpose, weekly activity plan, reminders, and active state are editable.
- Areas can be edited directly from the list by swiping or pressing and holding; detail also retains an Edit button.
- The Areas add menu gives equal prominence to **Add Custom Area** and **Use a Template**.
- Deactivation keeps history but stops its active tasks from generating future Calendar Items.

### 23.3 Activity-plan aggregation

An Area's adherence evidence includes Actions attached directly to it and Actions inside all descendants.

```text
Baseball activity-plan adherence
  = direct Baseball task occurrences
  + all occurrences in every contained program/subcategory
```

The parent uses its own approved weekly plan for the aggregate adherence status. Opening a child shows that child's own plan and evidence. An Action is stored under exactly one Area and counted once in any single rollup. This rollup never becomes Goal Result progress.

The Categories screen exposes the full tree with direct navigation. A parent detail screen lists its immediate children and aggregates their actions once into the parent result.

### 23.4 Period-driven Area screen

An Area is not a second Goal dashboard and it is not a settings form. It answers **“Am I following the supporting plan in this Area?”**

The Area screen has one Day / Week / Month control. That single selection updates all content below it:

1. aggregate Action-plan adherence,
2. adherence of contained Focus Areas,
3. actions scheduled in the selected period,
4. completed versus planned occurrences for each action.

The primary tracking action is named for the user's Area: for example **Log Cricket Training**, **Log Weight**, or **Log Food or Nutrition**. Generic Areas without a special measurement log are tracked by completing their scheduled actions. A secondary **Add an Action** button is always available.

Goal progress remains on the Goals surface. Area plan adherence and Action tracking remain supporting evidence. Focus Areas are optional and never required just to create an Action.

### 23.5 Fast generic creation

Both category creation and task creation include an optional **Inside** picker:

- `Top-level area`
- Any existing category path, such as `Baseball › Driveline`

This keeps the common case simple while supporting schedules organised by coach, class, subject, program, project, training provider, or any other user-defined system.

---

## 24. Mobile Schedule

The supplied schedule establishes a second planning surface in addition to Today. Its category names remain examples rather than built-in domains. On iPhone, legibility and fast action take priority over reproducing a desktop-sized timetable grid.

### 24.1 Purpose

Today remains the execution view. Schedule is the planning and balance view. It must answer:

- Where are the fixed commitments and available gaps?
- Is training, learning, work, recovery, and leisure distributed realistically?
- Which program or category owns each block?
- Are repeated activities visible as separate occurrences?

### 24.2 Interaction and layout

- The dedicated **Week** tab opens the Schedule with the current week and today selected.
- A seven-day strip shows weekday, date, and action count without compressing event text into narrow columns.
- Previous and next controls move one week at a time; tapping the date range opens a graphical date picker.
- Selecting a date reveals one chronological agenda grouped into Morning, Afternoon, and Evening.
- Each action card shows time, duration, action name, Area identity, current status, and a clear disclosure affordance.
- Tapping an action opens its details and full-width **Record as Done** and **Skip** controls.
- Empty days offer one centred, full-width **Add an Action** control.
- The view generates missing Calendar Items using the same `PlanningService` used by Today. It does not create a parallel scheduling model.

### 24.3 Shared interaction quality

- Every tappable control has a minimum 44-point hit target.
- The primary action in a screen or sheet is full-width, visually dominant, and has centred text.
- Secondary actions use the same geometry and alignment, with quieter colour.
- Adjacent compact actions have equal flexible widths so labels do not look misaligned.
- Icons support a clear label; they do not replace essential wording.
- Cards use consistent corner radii, internal spacing, and semantic system colours.

### 24.4 Physical-device readiness

The generated Xcode project uses automatic code signing. It must not set `CODE_SIGNING_ALLOWED = NO`, because that prevents installation on a physical iPhone. The developer still chooses their Apple Account team in Xcode; team identity is personal configuration and is never hard-coded in the repository.

---

## 25. Family Profiles, Reusable Plans and Data Safety

### 25.1 Household profiles, not mixed users

Version 1 supports multiple local household Profiles on one device. A Profile may be a Parent, Child, or Individual. Profiles are optional people, not hard-coded family slots. A child profile is never required and the product must not assume every user has a child. This is not yet a cloud account or permission system.

Every Profile owns separate:

- categories and hierarchy,
- activities and schedule rules,
- Calendar Items and Sessions,
- progress and confidence,
- nutrition, weight and sport logs,
- units and goals.

The selected Profile is shared across Dashboard, Today, Week, Categories and Progress, and the last selection is restored after relaunch. Every major screen exposes the same Profile picker. **Manage Profiles** creates, edits, hides or restores adults and children; switching never blends their results. Each profile supports an editable name and optional photo. Photos are resized before storage and included in family backup.

### 25.2 Smooth first-run setup

A fresh install begins with one neutral **My Profile** owner and generic basics. It does not create `Junior`, a named parent, or sport-specific family members. Existing installs retain all current profiles and history; an unwanted sample profile can be renamed or hidden rather than destructively removed.

New Profile creation asks for a user-approved starter plan:

- Blank - choose everything
- Balanced basics
- Student and sport
- Health and career

Starter plans create editable categories and a small number of realistic example tasks. They are not prescriptions. The app never silently adds sport-specific categories on later launches, and user-edited relationships are never overwritten by seed logic.

The normal add menu continues to offer equal choices:

- Add Custom Category
- Use a Template

### 25.3 Saved templates

Any category detail can save the category and its direct tasks as a reusable local template. The snapshot preserves:

- name, pillar, purpose, icon and colour,
- weekly session and minute targets,
- task targets and units,
- repeat type, selected weekdays, daily/weekly counts,
- exact interval, start time and duration.

Saved templates are visible to every Profile on the device under **My Saved Templates**. Applying one always opens the review screen before creation. Removing a saved template does not delete categories already created from it.

### 25.4 Persistence and backup

SwiftData persists automatically across normal app and phone restarts. Local persistence alone does not protect against app deletion, device loss, or storage corruption.

**Backup & Restore** exports one versioned JSON document containing all household Profiles, Goals, Area Contributions, Result Measures, Result Entries, Areas, Actions, calendar history, Sessions, nutrition records and photos, weights, sport logs, and saved templates. Schema 2 writes the Goal system; restore accepts schema 1 and 2 and merges by stable UUID.

The JSON backup is portable but not encrypted. The UI must warn the user to store it privately because it can contain child, health and family information. Cloud sync and role-based access remain later milestones; the backup format must not be described as live multi-device sync.

### 25.5 Calendar interaction

The Week grid is not a static report. A user may tap a block to inspect its date, time, duration, category and status, then record it Done or Skip that occurrence. Today's column displays a current-time line. Today remains the fastest execution surface, while Week remains the planning and balance view.

### 25.6 Parent-managed and self-managed profiles

Every Profile records an access intent:

- **Parent-managed:** a parent or guardian records plans, completions and health/sport information for the person on the parent's current device.
- **Self-managed:** the person records and manages their own plan. In the local version this still means the current device; it must not be presented as live access from another phone.

A child with no phone therefore needs no account. The parent simply uses the child Profile locally. A child with their own phone requires a later **Family Sync** capability before both devices can safely share the same Profile. That capability must include:

- a household account and stable member identity distinct from a Profile,
- parent/guardian invitation and approval,
- explicit roles such as Owner, Guardian, Member and Child,
- per-Profile grants for view, plan, record and sensitive-health access,
- revocation, device removal and an audit trail for family-management changes,
- conflict-safe synchronization and clear offline behaviour,
- age-appropriate consent, privacy and data deletion controls.

Profile photos, names and local management intent do not create an online identity. The UI must clearly label Family Sync as unavailable until its security and privacy model is implemented end to end.

### 25.7 Paid household management

Paid access is an entitlement attached to the household account, not a Boolean stored on a child Profile. The intended production model is:

```text
Account → Household → Membership/Role → Profile access grants
                    ↘ Subscription entitlement → enabled limits/features
```

StoreKit 2 may sell the subscription, but a server must validate transactions and authoritatively publish the household entitlement to every device. Suggested packaging remains subject to product validation:

- **Free/local:** one-device use, manual backup and a small number of locally managed Profiles.
- **Family:** multi-device sync, invitations, parent/guardian controls, more members and shared templates.
- **Coach/organisation later:** roster and programme workflows only after family permissions are proven safe.

A downgrade must never delete Profile data. It may stop new invitations or cloud collaboration while preserving local read/export access. Billing must not be used to hold a family's existing health or child data hostage.

## 26. User-Facing Mental Model

The persistence model may continue to use `AppCategory` and `Activity`, but the primary interface uses only these everyday concepts:

1. **Goal** — the measurable result the person wants.
2. **Area** — the organised part of life that supports Goals, such as Baseball, School, Nutrition or Software Development.
3. **Task** — a repeatable or one-time thing the person does inside an Area.
4. **Result** — evidence entered when it becomes available, such as a mock-test score, weight or throwing velocity.
5. **Today** — Tasks and Result check-ins due now.

The normal creation path is therefore:

```text
Choose or create an Area → connect a Goal → do today's Tasks → enter a Result when available
```

The interface must not require a user to understand category trees, domain entities, parent IDs, pillars, target schemas or template terminology before adding the first useful action. These rules apply:

- The primary Areas screen shows top-level Areas only. Optional Sub-areas appear after opening their parent.
- Goals remain a dedicated tab that always lists every active Goal and names its connected Areas.
- Every main `+` menu uses explicit choices: **Add a Task**, **Add an Area**, or **Start from an Area Template**.
- A new Task may quick-create a simple top-level Area without asking hierarchy questions.
- Numeric targets are optional and collapsed by default.
- Icons, colours, relationships, reminders and Sub-areas are progressive options.
- Starter content is called an **Area Template** only at the point of selection; the created record is an Area.
- Empty states teach with real examples rather than exposing implementation language.

The UI should make the common case fast while preserving advanced recurrence, relationships and hierarchy for people who need them.

### 26.1 Product patterns adopted for the simplified first version

Current market patterns reinforce a progressive approach:

- Use a small number of understandable tracking choices and editable templates rather than exposing a schema during setup.
- Open on work due today; deeper organisation should not obstruct checking off a Task.
- Keep Goals, Tasks and habits linked, but show outcome progress separately from completion effort.
- Use Areas primarily to group and filter related Tasks, not as another kind of Goal.
- Show immediate target status, a weekly summary and longer-term trend comparisons.
- For weight-related Goals, favour sustainable check-ins and never imply an unsafe deadline or automatically prescribe a target for a child.

For LifeOS this means the bottom navigation is **Today · Areas · Goals · Schedule**. Goal progress and supporting effort live together in Goals, so a fifth ambiguous Progress tab is unnecessary. Starting from a template creates an Area with editable Tasks; a Goal and Result definition remain explicit choices rather than silent additions. Advanced hierarchy remains available after setup, never before the first useful Task.

## 27. Generic Sport Tracking

Baseball is an optional starter Area, never a product-level assumption. Any Area explicitly configured for **Sport training**—such as Cricket, Soccer, Tennis, Swimming or Baseball—receives the same sport log using that Area's editable name, icon and weekly target. Runtime behavior never depends on matching an editable name.

Sport records belong to both a Profile and a Sport Area. The first generic logger records session type, duration, optional repetitions, perceived effort, soreness and notes. Sport-specific measurements may be added later as user-defined fields; they must not be forced onto unrelated sports.

### 27.1 Explicit Area tracking capability

Every Area stores one tracking capability: **Tasks only**, **Food & nutrition**, **Body weight**, or **Sport training**. The user chooses it when creating or editing an Area. Sub-areas may inherit the initial choice but remain independently editable. Existing Version 1 records receive a one-time compatibility mapping; after that migration, renaming an Area cannot change its tracker or progress semantics.

### 27.2 Editing and archival

Tasks, Goals and Result Measures have active/archive state. Archival removes future scheduling and reminders while retaining historical Calendar Items, Sessions and Result Check-ins. Goals, their supporting Areas, Result Measures, and individual Result Check-ins are editable. Destructive history deletion is intentionally not the normal Version 1 workflow.

### 27.3 Persistence failures

No user-initiated save may silently discard an error. Failed saves remain on the current form and show a clear recovery message. Initial seeding is part of persistent-store preparation; if it fails, the app opens the same recovery gate as any other store failure.

---

## Closing

> **The calendar is not the source of truth. Activities are the source of truth; the calendar is their planned daily expression, and Sessions are the honest record of what happened.**

LifeOS should help a person prepare the day, live it, record it honestly, and learn from it—without getting in the way.
