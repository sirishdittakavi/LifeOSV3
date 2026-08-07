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
| Profile preferences and goals | ✅ First version | kg/lb display, body goal and daily nutrition targets; Area-specific goals live inside each Area |
| Improvement category model | ✅ First version | Generic editable hierarchy, profile ownership, weekly targets, purpose, related areas and active state |
| Category templates | ✅ First version | Built-in library, optional profile starter plans, and locally saved reusable category/task templates |
| Confidence dashboard | ✅ First version | Today/week/month category progress, status, evidence confidence and next action |
| Category navigation | ✅ First version | Dashboard → nested category detail; list-row edit, custom/template creation and safe deactivation |
| Plain-language planning UX | ✅ First version | User-facing model is Areas → Actions → Today; hierarchy and tracking options are progressive, not front-loaded |
| Activity model | ✅ First version | Manual/template/AI-approved source |
| Schedule rule | ✅ First version | Once, daily, selected weekdays, any count per day/week, exact minute intervals |
| Calendar item | ✅ First version | Every calendar entry originates from an Activity |
| Today timeline | ✅ First version | Planned day in chronological order |
| Mobile schedule | ✅ First version | Seven-day strip, focused daily agenda, graphical date jump and interactive action cards |
| Mark Done / Skip | ✅ First version | Status and actual timestamps retained |
| Add task manually | ✅ First version | Fast task + inline category creation, exact numeric targets, time, duration and flexible repeat |
| Daily nutrition log | ✅ First version | Barcode lookup, label-photo OCR, saved photos, manual editing, macros, water and daily totals |
| Body-weight log | ✅ First version | Canonical kg storage, kg/lb display, goal distance, raw scale data and transparent 7-entry trend |
| Sport training log | ✅ First version | Uses the user's Sport Area name; generic sessions, repetitions, duration × effort workload and soreness trend |
| Seed templates | ✅ First version | Neutral single-profile start; optional starter plans for any added adult or child |
| Timer session | ⬜ Next | Basic data model present; dedicated timer screen next |
| Multiple tracking fields | ⬜ Next | Activity supports primary unit in first code version |
| Goals and measurements | ⬜ Next | Domain decision retained, UI deferred |
| Notifications | ✅ First version | Approved category enables task-time reminders and a Sunday weekly review |
| JSON backup/restore | ✅ First version | Full-family portable export and stable-ID merge restore, including photos and templates |
| Repository protocol | ⚠️ Partial | Planning service separated; full persistence abstraction next |
| Family sync and accounts | ❌ Deferred | Secure child invitations, permissions and multi-device sync require a cloud identity service |
| Paid household management | 📐 Designed | StoreKit entitlement plus server-authoritative household/member limits; implementation deferred |

---

## 1. The Core Idea, in Plain Language

LifeOS helps a person define what matters, prepare a realistic day, record what actually happened, and learn whether repeated effort is producing improvement.

The product is not centred on isolated activities or charts.

It is centred on the person's **improvement areas expressed through the day**.

```text
Goals and responsibilities
        ↓
Activities
        ↓
Schedule rules
        ↓
Today's calendar
        ↓
Done / skipped / rescheduled / unplanned
        ↓
Actual sessions and measurements
        ↓
Weekly learning and better future planning
```

Every screen should answer:

> **What should I do next to make meaningful progress?**

The Dashboard answers whether improvement areas are on track. Today remains the execution surface for the next scheduled action.

---

## 2. Core Product Decisions

| # | Decision |
|---:|---|
| 1 | **The Today calendar is the primary product surface.** |
| 2 | **Every calendar item originates from an Activity.** No unclassified calendar-only event exists. |
| 3 | **Each profile owns a separate calendar.** Parents and children have separate activities, plans, and history. |
| 4 | **Activities may be created manually, selected from templates, or suggested by AI—but AI/template suggestions require approval.** |
| 5 | **Category is mandatory for every Activity.** Tags are optional and support later analysis. |
| 6 | **Planned and actual values are stored separately.** Historical plans are never overwritten by actual results. |
| 7 | **A one-time manual event still creates a one-time Activity plus a Calendar Item.** It may later be saved as reusable. |
| 8 | **Complete-day tracking is supported but not forced.** LifeOS must not become surveillance or require accounting for every minute. |
| 9 | **Daily and weekly schedules are generated from activity rules, then remain editable by the user.** |
| 10 | **The first coding iteration prioritises the calendar/activity loop before advanced goals, AI, or cloud sync.** |

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
       ├── Category
       ├── Goal                         [next iteration]
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
       ├── Measurement                 [additional biometrics next iteration]
       └── Progress / Insight           [next iteration]
```

### Definitions

- **Profile** — the person whose life or progress is represented.
- **Category** — the broad grouping, such as Career, Education, Health, Nutrition, Baseball, or Software Development.
- **Activity** — a reusable definition of what the person may do.
- **Schedule Rule** — when and how often the Activity should occur.
- **Calendar Item** — one planned or unplanned occurrence on a specific day.
- **Session** — what actually happened, including timing and measured values.
- **Tag** — optional detail used for filtering and future analysis.

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

The first screen should feel like a useful daily calendar, not a statistics dashboard.

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
      ↓
JSON Export / Restore                  [next milestone]
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
- Dashboard period switching: Today, Week and Month
- Per-category Complete, On track, Needs attention, Behind, Insufficient data and No target today states
- Separate High, Medium and Low evidence confidence
- Category detail with purpose, task schedule, related areas and specialist tracking
- Local task reminders and weekly category review reminders

Not yet included:

- General Goal entity and cross-domain goal rollups
- Full timer screen
- Multiple custom tracking fields
- Additional custom biometrics beyond weight
- Weekly planning distribution
- JSON export/restore
- Face ID/PIN
- Cloud sync
- AI API

---

## 16. Next Iteration

Priority order:

1. Athlete onboarding with parent/coach-set, age-appropriate goals
2. Repeat foods, recipes, food search, and meal copy/paste
3. Apple Health weight import/export and connected-scale interoperability
4. Daily readiness check-in: sleep, energy, soreness, stress and notes
5. Baseball assessments, drill templates, video attachments and structured game stats
6. Weekly review connecting planned work, completed work, nutrition, body trend and workload
7. JSON export, auto-snapshot, restore and repository protocol
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
3. **Goals belong to the correct owner.** Body and nutrition goals belong to a Profile; weekly sport targets belong to each editable Sport Area.
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

## 21. Improvement Areas and Confidence Dashboard

### 21.1 Category hierarchy

LifeOS uses a hierarchy plus explicit relationships:

```text
Profile
└── Improvement Pillar
    └── Improvement Category
        ├── Purpose
        ├── Weekly session and minute commitments
        ├── Tasks / habits / activities
        ├── Measurements and specialist tracker
        ├── Related category IDs
        └── Reminder policy
```

Pillars currently supported:

- Physical Development
- Sport Development
- Health & Nutrition
- Learning & Career
- Life & Relationships

Categories are owned by exactly one Profile. Existing shared categories are upgraded non-destructively and activities retain their history.

Relationships are not inheritance and do not duplicate facts. A Sprint Technique Session may have Speed as its primary category while Speed is shown as supporting Baseball. The Session is counted once; the relationship explains context.

### 21.2 Template and custom setup

Every category begins through one of two paths:

```text
Choose template                    Start custom
      ↓                                 ↓
Review purpose, tasks, targets, schedule and reminder
      ↓
User / parent / coach approves
      ↓
Category and activities are created
```

Templates are editable defaults, never silent prescriptions. The current template library includes Baseball, Software Development, Mobility, Speed, Strength, Nutrition, Weight Improvement and Recovery.

Required configuration:

- Category name and pillar
- Purpose: why this area matters
- Weekly target sessions and/or minutes
- At least one task for generic categories, or a specialist logger for Nutrition, Weight and Sport Areas
- Optional connected areas
- Optional reminder approval

### 21.3 Dashboard periods

The Dashboard is the first product surface and offers:

```text
Today | Week | Month
```

**Today** uses scheduled tasks due today. Nutrition counts a day with at least one food log. Flexible weekly categories with no scheduled task show `No target today` rather than a false failure.

**Week** uses the category's approved weekly session and minute commitments.

**Month** derives a transparent target proportional to the number of days in the month:

```text
monthly target = ceil(weekly target × days in month ÷ 7)
```

Monthly views are for consistency and direction. They must not imply that minutes in unrelated categories are interchangeable.

### 21.4 Status calculation

Each category has one status:

- **Complete** — session target reached and minute target reached when configured.
- **On track** — completed sessions are at least 85% of expected pace for the elapsed period.
- **Needs attention** — below pace, but remaining scheduled/flexible opportunities can still meet the target.
- **Behind** — the current remaining opportunities cannot meet the target.
- **Insufficient data** — a period target or evidence source is missing.
- **No target today** — the category is active but has no action scheduled today.

Status never silently changes targets. `Behind` must offer a choice: complete/reschedule work or revise the commitment.

### 21.5 Confidence calculation

Confidence describes evidence quality, not motivation or predicted health:

- **High confidence** — target is complete, or at least 80% of due tasks have an explicit Done/Skipped/Rescheduled decision.
- **Medium confidence** — 40–79% of due tasks have a decision, or a specialist category is configured but has limited current evidence.
- **Low confidence** — fewer than 40% of due tasks have a decision or no reliable task/evidence source exists.

Status and confidence are always shown separately. `On track · Low confidence` is valid and should prompt logging, not celebration based on missing evidence.

### 21.6 Dashboard presentation

The top summary reports category coverage rather than a blended life score:

```text
4 of 6 active categories are complete or on track
1 needs attention
1 has insufficient data
```

Every category card shows:

- Progress ring for its own primary commitment
- Completed/target sessions and minutes
- Status
- Confidence
- One next action
- Link to the category detail

The category detail shows purpose, period progress, tasks/habits, connected areas, reminder state, and the relevant specialist logger.

### 21.7 Reminder policy

Reminders require explicit approval at category setup or edit time.

- Daily and selected-weekday activities use their planned start time.
- Multiple-times-per-day activities notify at every occurrence that fits before midnight.
- Times-per-week activities divide the requested count across preferred days; if a day receives multiple occurrences, the exact minute interval is used.
- One-time activities notify only if their fire date is still in the future.
- An enabled category receives a Sunday weekly-review reminder.
- Disabling reminders removes pending requests for the category and its activities.
- Notification denial never blocks local planning or tracking.

Dynamic catch-up notification timing is a later milestone because it requires reliable background progress evaluation. The current dashboard still provides the exact catch-up action whenever opened.

### 21.8 Safety and honesty

- Do not require every category every day; cadence belongs to the approved plan.
- Do not shame a child for weight, nutrition, soreness or missed work.
- Do not call workload an injury predictor.
- Do not infer causation from connected categories.
- Do not hide incomplete logging behind a green ring.
- Do not duplicate one Session across related categories.

---

## 22. Flexible Task Recurrence and Fast Creation

The creation flow uses the user's language: **New Task** and **Improvement Category**. A task cannot be saved without a category because category progress is the reason for tracking it. A new category can be created inline without leaving the task form.

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

Only occurrences whose start time is before midnight belong to that day. The form explains the resulting schedule before Save.

For times per week, the requested count is divided as evenly as possible across the selected preferred weekdays. Earlier selected days receive any remainder. When the weekly count exceeds the number of preferred days, the additional same-day occurrences use the exact interval.

Each occurrence becomes its own Calendar Item. Its stable uniqueness rule is:

```text
Activity ID + calendar date + planned start time
```

This prevents duplicate generation while allowing the second, third, or fourth occurrence to exist independently. Each occurrence can therefore be completed, skipped, or rescheduled separately.

### 22.3 One schedule engine

`PlanningService.scheduledStartMinutes` is the single schedule calculation used by:

- Today timeline generation
- Daily/weekly/monthly category progress
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

## 23. Generic Improvement Hierarchy

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

Relationship answers **"what other area can this support?"** A category may relate to many categories.

For example, Driveline may be contained by Baseball, while Mobility is a separate improvement area related to Baseball. Moving Mobility under Baseball would be a user choice, not an inferred rule.

### 23.2 Editing rules

- A category can be top-level or placed inside any category owned by the same Profile.
- Nesting may continue beyond one level when useful.
- A category can be moved later without rewriting activity or calendar history.
- The category itself cannot be selected as its parent.
- Descendants cannot be selected as parents; cycles are invalid.
- Deactivating a parent does not silently delete its children or tasks.
- Breadcrumbs show the full path when choosing a category for a task.
- A category's name, parent placement, pillar, icon, colour, purpose, weekly targets, reminders, and active state are editable.
- Categories can be edited directly from the list by swiping or pressing and holding; detail also retains an Edit button.
- The Categories add menu gives equal prominence to **Add Custom Category** and **Use a Template**.
- Deactivation keeps history but stops its active tasks from generating future Calendar Items.

### 23.3 Progress aggregation

The Dashboard shows top-level improvement areas so one task is not presented as several independent life goals. A top-level area's evidence includes tasks attached directly to it and tasks inside all descendants.

```text
Baseball dashboard progress
  = direct Baseball task occurrences
  + all occurrences in every contained program/subcategory
```

The parent uses its own approved weekly target for the aggregate status. Opening a child shows that child's own target and evidence. A task is stored under exactly one category and counted once in any single rollup.

The Categories screen exposes the full tree with direct navigation. A parent detail screen lists its immediate children and aggregates their actions once into the parent result.

### 23.4 Period-driven Area screen

An Area is not a second dashboard and it is not a settings form. It is the simplest answer to **“Am I doing enough for this Area?”**

The Area screen has one Day / Week / Month control. That single selection updates all content below it:

1. aggregate progress and confidence,
2. the status of contained Focus Areas,
3. actions scheduled in the selected period,
4. completed versus planned occurrences for each action.

The primary tracking action is named for the user's Area: for example **Log Cricket Training**, **Log Weight**, or **Log Food or Nutrition**. Generic Areas without a special measurement log are tracked by completing their scheduled actions. A secondary **Add an Action** button is always available.

This avoids separate, competing “Progress”, “Tracking”, and “Tasks” destinations. Focus Areas remain optional and subordinate; they are never required just to create an action.

### 23.5 Fast generic creation

Both category creation and task creation include an optional **Inside** picker:

- `Top-level improvement area`
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

**Backup & Restore** exports one versioned JSON document containing all household Profiles, categories, tasks, calendar history, Sessions, nutrition records and photos, weights, sport logs, and saved templates. Restore merges by stable UUID so importing the same file again does not duplicate records.

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

The persistence model may continue to use `AppCategory` and `Activity`, but the primary interface must use only three everyday concepts:

1. **Area** — something the person wants to improve, such as Baseball, School, Health or Software Development.
2. **Action** — a repeatable or one-time thing the person does, such as Batting Practice, Homework or Walk.
3. **Today** — the actions due now and the fastest place to complete or record them.

The normal creation path is therefore:

```text
Choose or create an Area → name the Action → choose when it happens → Save
```

The interface must not require a user to understand category trees, domain entities, parent IDs, pillars, target schemas or template terminology before adding the first useful action. These rules apply:

- The primary Areas screen shows top-level Areas only. Optional Focus Areas appear after opening their parent.
- Every main `+` menu uses explicit choices: **Add an Action**, **Add an Area**, or **Start from a Plan**.
- A new Action may quick-create a simple top-level Area without asking hierarchy questions.
- Numeric targets are optional and collapsed by default.
- Icons, colours, related areas, reminders and Focus Areas are progressive options.
- Starter content is called a **Plan** in the interface. `Template` remains an internal storage term.
- Empty states teach with real examples rather than exposing implementation language.

The UI should make the common case fast while preserving advanced recurrence, relationships and hierarchy for people who need them.

## 27. Generic Sport Tracking

Baseball is an optional starter Plan, never a product-level assumption. Any Area in the **Sport Development** group—such as Cricket, Soccer, Tennis, Swimming or Baseball—receives the same sport log using that Area's editable name, icon and weekly target.

Sport records belong to both a Profile and a Sport Area. The first generic logger records session type, duration, optional repetitions, perceived effort, soreness and notes. Sport-specific measurements may be added later as user-defined fields; they must not be forced onto unrelated sports.

---

## Closing

> **The calendar is not the source of truth. Activities are the source of truth; the calendar is their planned daily expression, and Sessions are the honest record of what happened.**

LifeOS should help a person prepare the day, live it, record it honestly, and learn from it—without getting in the way.
