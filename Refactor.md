# LifeOS — REFRACTORING.md

**Status:** Approved architecture direction before UI/UX V2  
**Goal:** Refactor the foundation without redesigning the UI yet or breaking existing data.

## 1. Target Architecture

```text
SwiftUI View
    ↓
ViewModel
    ↓
Use Case / Application Service
    ↓
Repository Protocol
    ↓
SwiftData Repository
    ↓
SwiftData
```

Rules:
- Views do not contain persistence logic.
- ViewModels coordinate UI state and call use cases.
- Business rules and aggregation live in use cases/services.
- SwiftData is accessed through repositories.
- Future cloud/API storage should not require rewriting screens.

## 2. Core Domain Rule

Separate **reusable definitions** from **actual historical records**.

| Reusable definition | Actual record |
|---|---|
| Activity | ActivitySession |
| ScheduleRule | CalendarItem |
| FoodDefinition | FoodLogEntry |
| MealTemplate | FoodLogEntries |
| MeasurementDefinition | MeasurementEntry |
| Goal / Target | Derived Progress |

Changing a reusable definition later must never rewrite history.

## 3. Historical Snapshot Rule

Historical records store the values that were true when they were logged.

Example:

```text
Monday:
My Breakfast = 25 g protein

Tuesday:
Template changed to 30 g protein

Monday remains 25 g.
Future logs may use 30 g.
```

Historical calculations must use the stored snapshot, not the current template.

## 4. Universal Editability

Anything entered by the user must be correctable later.

Historical records should support where appropriate:

- View
- Edit
- Delete
- Duplicate

Reusable definitions should support:

- Create
- Edit
- Duplicate
- Archive

Where useful:
- Save as reusable

## 5. Activity Domain

```text
Activity
    ↓
ScheduleRule
    ↓
CalendarItem
    ↓
ActivitySession
```

### Activity
Reusable definition such as Java Practice, Gym, Swimming, Batting, Reading.

### ScheduleRule
Defines when an Activity should appear.

V1 scheduling:
- once
- daily
- selected weekdays

### CalendarItem
The planned occurrence for a specific date/time.

### ActivitySession
What actually happened.

**Planned and actual values must stay separate.**

Example:

```text
Planned: Java Practice 7:00–7:45 PM
Actual:  7:12–7:39 PM, 27 minutes
```

Completing/editing a session must not overwrite the original plan.

## 6. Nutrition Domain

Nutrition should be a typed domain because one food entry contains multiple values.

### NutritionSnapshot
Initial fields:
- calories
- protein
- carbohydrates
- fat
- water

### FoodDefinition
Reusable food:
- name
- default serving
- nutrition per serving
- favorite/archive state

### FoodLogEntry
Actual consumption:
- food name snapshot
- meal type
- servings
- nutrition snapshot
- occurredAt
- notes
- source
- optional source FoodDefinition/MealTemplate reference

Meal types:
- breakfast
- lunch
- dinner
- snack
- other

### MealTemplate
Reusable meal, for example **My Usual Breakfast**.

### MealTemplateItem
Food + serving quantity inside the template.

Logging a meal template creates historical FoodLogEntries with snapshots.

## 7. Nutrition V1 Requirements

Architecture must support:

- Breakfast / Lunch / Dinner / Snacks
- Manual food entry
- Saved foods
- Saved meals
- Recent foods
- One-tap **Add to Today**
- Serving adjustment
- Edit incorrect food logs
- Delete food logs
- Immediate recalculation of calories/protein/etc.

Daily totals must always come from FoodLogEntries.

## 8. Goals and Progress

Examples:

```text
Protein        100 g/day
Swings         100/day
Java Practice   45 min/day
Active Time     60 min/day
```

Progress is derived:

```text
Actual Records
      +
Goals
      ↓
Progress Engine
      ↓
ProgressMetric
```

Generic `ProgressMetric` should expose:

- title
- current value
- target value
- unit
- percentage/progress
- status text
- destination

Do not create separate hard-coded dashboard logic for Protein, Baseball, Coding, etc.

## 9. Today / Dashboard Architecture

Dashboard is a **read model**, never another source of truth.

```text
CalendarItems ───────┐
ActivitySessions ────┤
FoodLogEntries ──────┤
Measurements ────────┤
Goals ────────────────┤
                     ↓
             TodaySummaryService
                     ↓
               TodayViewModel
                     ↓
                 Today UI
```

Final conceptual Today structure:

1. Right Now
2. Today's Plan
3. Progress at a Glance
4. Quick Log

Avoid duplicates such as:
- Today's Targets + Progress at a Glance
- Plan tiles + the same Today's Plan entries
- independent Protein totals on Dashboard and Nutrition

There must be one source of truth.

## 10. Measurements

Prepare:

```text
MeasurementDefinition
MeasurementEntry
```

Examples:
- weight
- sleep duration
- bat speed
- sprint time
- assessment score
- confidence

Historical measurement entries should snapshot their name/unit.

## 11. Repository Boundaries

Use repositories by domain, not one giant repository.

Examples:

```text
ActivityRepository
ActivitySessionRepository
CalendarRepository
FoodRepository
FoodLogRepository
MealTemplateRepository
GoalRepository
MeasurementRepository
```

SwiftData implementations live behind these protocols.

## 12. Application Use Cases

Important use cases include:

### Activity
- CreateActivity
- UpdateActivity
- GenerateTodayPlan
- StartActivity
- CompleteActivity
- EditActivitySession
- DeleteActivitySession

### Nutrition
- CreateFood
- UpdateFood
- LogFood
- EditFoodLog
- DeleteFoodLog
- CreateMealTemplate
- UpdateMealTemplate
- LogMealTemplate
- GetDailyNutritionSummary

### Dashboard
- GetTodaySummary

### Goals / Progress
- CreateGoal
- UpdateGoal
- CalculateProgress

### Measurements
- LogMeasurement
- EditMeasurement
- DeleteMeasurement

Do not create trivial use cases with no business purpose just to follow a pattern.

## 13. Important Non-Goal

Do **not** create one giant generic model:

```text
LifeOSEntry {
    calories?
    protein?
    swings?
    duration?
    sleep?
    weight?
    score?
    ...
}
```

Use:

```text
Shared lifecycle concepts
+
Typed domain models
```

LifeOS should be generic at the architecture/behavior level, not through a giant bag of optional fields.

## 14. Migration Safety

Before changing SwiftData schemas:

1. Inventory current models.
2. Map current model → target model.
3. Preserve existing UUIDs.
4. Prefer additive/optional changes first.
5. Avoid destructive migrations.
6. Backfill snapshots safely.
7. Verify existing user/sample data still loads.
8. Stop and explain before any change that risks data loss.

## 15. Refactoring Sequence

Do **not** refactor everything at once.

### Phase 1 — Persistence Boundary
Introduce repository protocols and reduce direct SwiftData access from screens/ViewModels.

### Phase 2 — Activity Separation
Confirm clear separation of Activity, ScheduleRule, CalendarItem and ActivitySession.

### Phase 3 — Edit/Delete Infrastructure
Make historical records safely editable/deletable.

### Phase 4 — Nutrition Domain
Introduce FoodDefinition, FoodLogEntry, NutritionSnapshot, MealTemplate and MealTemplateItem.

### Phase 5 — Nutrition Aggregation
Create one daily nutrition aggregation source. Add/Edit/Delete must immediately update totals.

### Phase 6 — Goals + Generic Progress
Introduce Goal/Target and generic ProgressMetric/ProgressService.

### Phase 7 — Today Read Model
Create TodaySummary/GetTodaySummary and remove duplicate dashboard calculations.

Each phase should:
- build successfully
- run relevant tests
- preserve current behavior
- be committed separately

## 16. Minimum Tests

### Activity
- planned values remain unchanged after completion
- actual duration stored separately
- editing session changes actual data only
- deleting a session does not delete Activity

### Nutrition
- food log contributes to daily totals
- editing a food log recalculates totals
- deleting a food log recalculates totals
- meal template creates correct food logs
- changing a template does not modify historical food logs
- serving multiplier adjusts nutrition correctly

### Progress / Dashboard
- 72 / 100 protein produces 72% progress
- zero/missing targets do not crash
- dashboard derives values from source records
- no independent duplicate nutrition totals

## 17. Not Part of This Refactor

Do not add yet:

- barcode scanning
- external nutrition database
- photo/AI food recognition
- CloudKit/backend API
- Apple Health integration
- advanced AI coaching
- advanced charts
- micronutrient analysis
- major visual redesign

UI/UX V2 comes **after** this architecture is stable.

## 18. Success Criteria

Refactor is complete when:

- existing app still builds
- existing core workflows still work
- SwiftData access is behind repositories for refactored domains
- reusable definitions are separate from actual records
- planned and actual activity values are separate
- food/meal templates are separate from food history
- historical records use snapshots
- user-created records are editable/correctable
- Nutrition has one source for daily totals
- Dashboard derives rather than duplicates data
- dashboard metrics are generic
- core architecture contains no sport-specific assumptions
- future Today V2 and Nutrition V2 can be built without another domain rewrite

---

## Instructions for Claude

First **inspect the existing repository and produce a gap analysis only. Do not change code yet.**

Report:

1. current architecture
2. current SwiftData/domain models
3. mapping from current models to this target architecture
4. gaps
5. proposed migration/refactor phases
6. files likely to change
7. risks to existing data

Then stop for review.

After approval, implement **one phase at a time**, build/test, and commit each phase separately.

Do not redesign UI/UX during the refactor.
Do not expand scope.
If a change may cause data loss, stop and explain before making it.

---

## Progress Log

### Step 1 — Unify progress calculation (done)

`ProgressEngine`, `CategoryProgressEngine` and `GoalProgressEngine` each
reconstructed scheduled occurrences independently. `CategoryProgressEngine`
and `GoalProgressEngine` derived target counts purely from an Activity's
*current* schedule config, silently dropping stored `CalendarItem`s left
behind by an earlier schedule edit; `ProgressEngine` already merged stored
items with reconstructed ones correctly.

Added `PlanningService.reconstructedOccurrences` as the single canonical
merge (dedup by `OccurrenceIdentity`), and pointed all three engines at it.
Public signatures unchanged; no view call sites needed updates.

Commit: `ff62121` (plus `cbed17d`, an unrelated cleanup — see below).

### Step 2 — Verify and fix calendar scheduling (done, no production bug found)

Audited the schedule path (`Activity` fields → `PlanningService` →
`CalendarItem` generation → Today/Week display) against once, daily,
selected-weekdays, cross-week repetition, and edit-schedule reconciliation.
Step 1 did not touch this path — `scheduledStartMinutes`,
`generateMissingCalendarItems`, `reconcileUntouchedOccurrences`,
`occurrenceIdentity` and `duplicateCalendarItems` were all unchanged by it —
so there was nothing for Step 1 to have already fixed here.

Found no bug: weekday mapping matches Foundation's Sunday=1…Saturday=7 (and
DESIGN.md §13's own `weekdays` example), `.timesPerWeek`/`.selectedWeekdays`
schedule purely off a date's weekday with no per-week state so they repeat
identically indefinitely, start/end-date bounds are inclusive on both ends,
occurrence identity prevents duplicate generation, and
`EditTaskView.save()`'s reconcile-then-regenerate sequence correctly drops
only the occurrences that fell off the new schedule.

`.selectedWeekdays` previously only had indirect test coverage (via a
reconciliation test); added direct regression tests for weekday mapping,
cross-week repetition, and an end-to-end edit-schedule scenario. All 71
tests pass; app target builds. No production code changed.

Commit: `8b15b2d` (test-only, no production code changed).

### Step 3 — Safe activity deletion and archiving (done)

Audited whether the app could already: delete an accidentally created
Activity, remove one calendar occurrence, keep the recurring Activity
intact, preserve completed history, and archive instead of destructively
deleting when history exists.

Already working, left unchanged: removing one calendar occurrence, while
keeping the Activity intact, already works via **Skip This Occurrence**
(`WeekItemDetailView`/`TodayTimelineView`) — it takes the occurrence out of
the active plan, never touches the Activity, is reversible (Undo Skip), and
because the identity slot stays occupied it never regenerates. True
per-occurrence deletion with permanent exclusion isn't implemented, but
DESIGN.md §8 explicitly defers "exception dates" to a future iteration, so
this is out of scope, not a bug.

Missing, now fixed: there was no way to actually delete an Activity —
`isActive` toggling ("Archive") existed, but nothing let you remove a
truly accidental Task, and nothing enforced "archive instead of delete
when history exists." Added a Task Management section to `EditTaskView`
with a single Delete/Archive action (`PlanningService.hasAnyHistory` decides
which): no history → permanent delete of the Activity and its own
(necessarily untouched) CalendarItems; history exists → archives instead
(`isActive = false` + `reconcileUntouchedOccurrences`, the same primitives
the existing Area "Hide" flow already uses) and says so in the confirmation
dialog, so history is never silently discarded.

Files changed: `LifeOS/Engine/PlanningService.swift` (new `hasAnyHistory`),
`LifeOS/Views/EditTaskView.swift` (delete/archive UI + action),
`LifeOSUnitTests/PlanningServiceTests.swift` (regression test). 72/72 tests
pass; app target builds.

Commit: `1793c84`.

**Follow-up fix:** user-reported symptom after real use — deleting a
no-history Task removed today's and future occurrences correctly (proven by
`testDeletingActivityWithNoHistoryRemovesTodayAndFutureItemsWithoutOrphaning`),
but the screen that presented `EditTaskView` (`TaskDetailView` or
`WeekItemDetailView`) stayed open holding a direct reference to the now-deleted
Activity/CalendarItem, rendering it as a blank "Task" row. Added
`EditTaskView.onActivityDeleted` closure, invoked only on true delete (not
archive), so the presenter dismisses itself too. Both presenting call sites
updated. App builds; 74/74 tests pass. Commit: `583e461`.

### Step 4 — Today/Dashboard MVVM boundary (done)

Introduced `View -> ViewModel -> Service/Use Case -> Repository -> SwiftData`
for the Today screen only (per DESIGN.md §9's own `TodaySummaryService ->
TodayViewModel -> Today UI` architecture). `TodayTimelineView` no longer
computes derived state or touches `ModelContext` for `CalendarItem` writes
directly.

- `CalendarRepository` (protocol) / `SwiftDataCalendarRepository` — the new
  persistence boundary, wrapping `ModelContext` insert/save.
- `TodayViewModel` — a stateless struct (recreated fresh from the View's
  live `@Query` results on every access, so there's no separate sync step
  that could drift stale) holding every derived value that used to be a
  `private var` directly on the View (`todayItems`, `summary`,
  `activeItems`, `decidedItems`, `overdueItems`, `nextItem`,
  `restOfDayItems`, `dueResultMeasures`) plus the actions
  (`start`/`skip`/`undoSkip`/`generateTodayItemsIfNeeded`). Logic is
  unchanged, only relocated — verified against a fake `CalendarRepository`
  in `TodayViewModelTests.swift`, with no ModelContext/SwiftUI needed.
- `PlanningService`/`ProgressEngine` remain the Service/Use Case layer,
  called from inside `TodayViewModel` exactly as before.

Views other than Today were not touched (explicitly out of scope).

Files: `LifeOS/Engine/CalendarRepository.swift` (new),
`LifeOS/Engine/TodayViewModel.swift` (new), `LifeOS/Views/TodayTimelineView.swift`
(derived state/actions removed, delegates to `viewModel`), `Package.swift`
(both new files added to the testable target), `LifeOSUnitTests/TodayViewModelTests.swift`
(new, 3 focused tests). App builds; focused tests pass.
