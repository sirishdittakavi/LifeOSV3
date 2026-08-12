# LifeOS — Architecture.md

**Status:** Living architecture reference. Reflects both the implemented V1 architecture and the target direction from `LIFEOS_PRODUCT_ARCHITECTURE_UPDATE.md` (2026-08-11).
**Companion docs:** `DESIGN.md` (V1 product spec, still the source of truth for what's shipped), `Refactor.md` (refactor phase log, source of truth for what's changed and why).

This document exists to answer one question at each point in time: **what does LifeOS's architecture look like right now, and where is it headed?** It does not restate everything in `DESIGN.md` — it summarizes the shape and flags the gaps against the target direction below.

---

## 1. Product Direction

LifeOS is evolving from a task tracker into a **generic personal improvement platform**:

> Help people convert goals into activities, schedule them, execute them, measure progress, and continuously improve.

It is explicitly *not* a fitness app, coding app, sports app, or productivity app — it's a domain-agnostic system usable for sport, learning, career, health, creative skills, family, or any user-defined improvement area. This reframes several existing concepts (see §3–§9) from "the thing this V1 does" to "one instance of a generic capability."

The core flow the product is built around:

```text
Person → Area → Goal → Activity Template → Schedule → Activity Session → Measurements → Progress → Insights
```

---

## 2. Current Implemented Architecture (V1)

```text
SwiftUI View
      ↓
ViewModel                    [Today screen only — Refactor.md Step 4]
      ↓
Planning Service / Progress Engine / Category Progress Engine / Goal Progress Engine
      ↓
Repository (CalendarRepository)   [Today screen only — Refactor.md Step 4]
      ↓
SwiftData (ModelContext, direct access from most Views)
```

- **Views query SwiftData directly** via `@Query` everywhere except the Today screen, which now goes through `TodayViewModel` → `CalendarRepository`.
- **Business logic is unit-testable** where it's been extracted into `LifeOS/Engine/*.swift` (`PlanningService`, `ProgressEngine`, `CategoryProgressEngine`, `GoalProgressEngine`, `TodayViewModel`, `ProgressMetric`). These are the only parts of the codebase covered by the headless `LifeOSCorePackageTests` suite (see `Package.swift`).
- **No full repository layer yet.** `CalendarRepository` is the only repository; everything else (Activity, Goal, FoodEntry, WeightEntry, SportEntry, ActivitySession) is still read/written directly from Views via `ModelContext`.
- **Persistence is SwiftData**, versioned via `SchemaVersioning.swift` (`LifeOSSchemaV1`, `LifeOSMigrationPlan`). No migration to V2 has happened yet — the current schema is still the original release contract.
- **Progress calculation is unified** (Refactor.md Step 1): one canonical occurrence-reconstruction path (`PlanningService.reconstructedOccurrences`) backs `ProgressEngine`, `CategoryProgressEngine`, and `GoalProgressEngine`, so completion/target numbers can't silently diverge between screens.
- **`ProgressMetric`** (Refactor.md Step 7) is a generic `title/currentValue/targetValue/unit/statusText/destination` type, currently driving progress-bar fractions on Today's Plan cards. It is not yet the universal dashboard data source — most screens (Goals dashboard, Category detail) still render from their own domain-specific progress structs (`CategoryProgress`, `GoalProgress`) rather than through `ProgressMetric`.

---

## 3. Current Domain Model → Target Direction Mapping

| Target concept (update doc) | Current LifeOS model | Fit |
|---|---|---|
| Person | `Profile` | Close match. `Profile` already supports multiple people per install, each with isolated Goals/Activities/Schedules/Sessions. |
| Relationship (Parent/Coach/Mentor/Teacher, generic) | `ProfileKind` (adult/child/individual) + `ProfileManagementMode` (parentManaged/selfManaged) | **Gap.** Current model hardcodes a fixed two-role relationship (parent manages child) as an enum on `Profile` itself, not a generic `Person ↔ Relationship ↔ Person` edge. No coach/mentor/teacher concept exists. DESIGN.md §25.6 already flags real multi-device Family Sync as a deferred capability — the relationship model described in the update doc is a superset of that. |
| Area | `AppCategory` (generic hierarchy, profile-owned, pillar-grouped) | Good match already. Not sport/domain-specific; user-created and nestable. |
| Goal | `Goal` + `GoalAreaContribution` + `ResultMeasure` + `ResultEntry` | Good match. Already separates the goal, its supporting Areas, and typed evidence (number/rating/milestone/written). |
| Activity Template | `Activity` (reusable definition, `source`: manual/template/aiSuggestion/imported) | Good match. Already generic — no `BaseballActivity`/`MusicActivity` subclasses. |
| Schedule | `Activity`'s schedule fields (`repeatType`, `weekdays`, `occurrencesPerDay/Week`, etc.) + `PlanningService` | Good match, and the single-schedule-engine rule (`scheduledStartMinutes`) already matches "the same activity engine supports all domains." |
| Activity Session (actual) | `CalendarItem` (planned + actual timestamps/status) and `ActivitySession` (recordedValue + timing, DESIGN.md §10a) | Good match structurally — planned/actual are already separate records, never overwritten. |
| Dynamic, user-defined Measurements | `Activity.targetValue: Double?` + `targetUnit: String?` (one fixed numeric target); `ActivitySession.recordedValue: Double` (one fixed number) | **Gap.** Today an Activity has exactly one target/unit pair and one recorded value. The update doc's examples (Ground Balls + Fly Balls + Catches + Reaction Time + Throw Accuracy, tracked *simultaneously* on one Activity) need a one-to-many, user-configurable measurement definition per Activity, not a single scalar. This is the largest schema gap identified. |
| Progressive tracking (casual → serious → professional) | Not modeled explicitly | **Gap, but low-risk.** Today's single target/value model already serves "casual" (completion + duration) reasonably well. "Serious" (multiple measurements) and "professional" (structured multi-week programs with multiple targets) both depend on the dynamic-measurement gap above being closed first. |
| Dashboard ("5-second understanding") | `TodayTimelineView` (progress %, next task, completed list) | Good conceptual match already; DESIGN.md §12 and the Today screen's hero/plan-card layout were built around the same "one clear next action" idea. |
| Calendar ("not the main product," Today/Week only) | `WeeklyScheduleView` (7-day strip) + `TodayTimelineView` | Matches. No month view or complex calendar UI exists, consistent with "avoid becoming a complex calendar application." |
| Architecture Layers (View → ViewModel → Use Cases → Repository → Data Source) | Implemented for Today only (Refactor.md Step 4); everywhere else is View → SwiftData directly | **Partial.** Today is the reference implementation; extending it to Areas/Goals/Nutrition/Measurements is unstarted. |
| Data source: SwiftData now, Supabase/Postgres later | SwiftData only, no network layer | Not started. The existing Repository protocol boundary (`CalendarRepository`) is what would make a future swap possible without rewriting Views — but only for Today so far. |
| AI Direction (calculation engine first, AI later, AI never replaces core calculations) | No AI integration exists | Consistent by omission — nothing currently violates this, since there's no AI layer yet to potentially bypass the calculation engine. |
| Notification Engine (generic rule engine over scheduled/expected/actual) | `ReminderService` (schedule-driven local notifications per DESIGN.md §21.7) | **Partial.** Current reminders fire from the schedule itself (planned time), not from a rule engine reacting to planned-vs-actual deltas ("Activity missed," "Goal progress dropping," "Consistency improving"). Those would be new, derived-from-evidence rules layered on top of the existing scheduling. |

---

## 4. What This Means for Refactor.md

This document does not itself authorize any schema or code change. Per the update doc's own Implementation Rule, the sequence is: update docs → review models (this section) → identify migration risks (`Refactor.md`) → agree phases → then refactor. See `Refactor.md`'s "Product Architecture Update" entry for the risk assessment and open questions that follow from the mapping above.

---

## 5. Non-Goals (carried forward from DESIGN.md, still valid)

The update doc doesn't rescind any of DESIGN.md §17's deferred-feature list (barcode scanning, CloudKit, Apple Health, advanced AI coaching, micronutrient analysis, major visual redesign). It adds a longer-term platform direction on top of, not instead of, that V1 scope discipline. "Do not implement code changes based on this document yet" (the update doc's own words) applies until phases are agreed.
