# LifeOS — Domain Model V2 Proposal

**Status:** Design proposal only. No code, no SwiftData migrations, nothing implemented.
**Based on:** `Architecture.md`, `Refactor.md`, `LIFEOS_PRODUCT_ARCHITECTURE_UPDATE.md`.
**Purpose:** Define the future domain model — Person/Profile, Relationship, Goal, ActivityTemplate, ScheduleRule, ActivitySession, MeasurementDefinition, MeasurementEntry, and how progress is calculated across all of them — before any schema work begins.

---

## 1. Proposed Entity Diagram

```text
Profile ──────────────┬─────────────────────────────────────────────┐
  │                    │                                             │
  │ (participates in)  │ (owns)                                      │ (owns)
  ▼                    ▼                                             ▼
Relationship        Area (AppCategory)                             Goal
  │                    │                                             │
  │ links              │ (owns)                                      ├── GoalAreaContribution → Area
  ▼                    ▼                                             ├── ResultMeasure (primary + supporting)
Profile          ActivityTemplate ◄────────────────┐                 │      │
                       │                            │ optional link  │      ▼
                       │ (owns, 0..N)                │                │  ResultEntry (dated evidence)
                       ▼                            │                │
              MeasurementDefinition ─────────────────┘                │
                       │                                              │
                       │ (defines shape for)                          │
                       ▼                                              │
              ScheduleRule (embedded on ActivityTemplate)              │
                       │                                              │
                       │ generates                                    │
                       ▼                                              │
                 CalendarItem  (planned occurrence)                   │
                       │                                              │
                       │ fulfilled by (optional)                      │
                       ▼                                              │
                ActivitySession  (actual — what happened) ◄───────────┘
                       │                                     (may feed progress)
                       │ (owns, 0..N)
                       ▼
                MeasurementEntry (snapshot: name/type/unit + value)
```

Legend: solid arrows are ownership/composition (deleting the parent is the only thing that can remove the child, subject to history-preservation rules in §2); the `ActivitySession → Goal` dotted relationship in prose below is the *optional* auto-rollup path discussed in §9 and Open Question 3 — it is not a hard foreign key.

---

## 2. Entity Descriptions

### 2.1 Person / Profile

**Purpose.** Represents one individual whose life and progress LifeOS tracks. Already implemented as `Profile`; this proposal keeps it structurally as-is and adds the `Relationship` entity alongside it rather than inside it.

**Important fields.** `id`, `name`, `colorToken`/`avatar`, `isActive`. Domain-specific preference fields that exist today (`weightUnit`, `calorieGoal`, macro goals) stay on `Profile` — they're display/unit preferences, not identity.

**Change from current model.** `kind: ProfileKind` (adult/child/individual) and `managementMode: ProfileManagementMode` (parentManaged/selfManaged) are proposed for **eventual removal**, replaced by `Relationship` records. In V2, "is this a child profile a parent manages" becomes *"does an active Relationship of type `guardian` exist where I am the target and it grants `manage` permission"* — a query, not a hardcoded field. See Open Question 5 for how much of this to do now vs. later.

**Relationships.** Owns Areas, Goals, ActivityTemplates, CalendarItems, ActivitySessions, MeasurementDefinitions (via ActivityTemplate). Participates in zero or more `Relationship` records, as either side.

**Ownership.** Top-level. Nothing crosses a Profile boundary without an explicit `Relationship` grant.

**Examples.** Developer, Player, Student, Parent, Coach — the same Profile type regardless of role; role is expressed entirely through Relationships, not through a fixed `kind`.

**Historical data considerations.** Renaming a Profile, changing its avatar, or (in V2) changing its Relationships must never alter the meaning of historical records already attributed to it — records reference the Profile by stable `id`, never by a copied name, so this already holds today and carries forward unchanged.

---

### 2.2 Relationship

**Purpose.** A generic Person ↔ Person connection, replacing the hardcoded parent/child roles baked into `Profile` today. New entity — does not exist in the current model.

**Important fields.**
- `id`
- `subjectProfileID` — the profile being acted upon/observed (e.g., the child, the athlete, the mentee)
- `actorProfileID` — the profile with the grant (e.g., the parent, the coach, the mentor)
- `relationshipType` — user-facing label; extensible, **not** a closed enum of Parent/Coach/Teacher/Mentor. Store as a string with a small set of suggested starter values, exactly like `AppCategory` templates are suggestions, not a fixed vocabulary.
- `permissions` — a set, not implied by type: `view`, `edit`, `manageActivities`, `receiveNotifications`, `viewProgress`. Two relationships of the same `relationshipType` can carry different permissions (a coach who can view but not edit vs. one who can also manage the schedule).
- `status` — `pending` / `active` / `revoked`
- `createdAt`, `respondedAt`

**Relationships.** References exactly two Profiles (`subjectProfileID`, `actorProfileID`). Independent of Area/Goal/ActivityTemplate — permissions apply to the whole Profile, not a slice of it, in this first version (a finer-grained "this coach can only see Baseball, not grades" scope is a plausible future extension, not part of this proposal).

**Ownership.** Conceptually owned jointly by the two Profiles it connects; practically created by whichever side initiates it, with `status` tracking consent where consent is meaningful (see Open Question 5 — single-device parent-manages-child today needs no consent step at all, since it's the same physical install).

**Examples.**
- Parent relationship: actor = Adult profile, subject = Child profile, permissions = `{view, edit, manageActivities, receiveNotifications, viewProgress}`.
- Coach relationship: actor = Coach profile, subject = Player profile, permissions = `{view, viewProgress}` (read-only observation, no edit).
- Mentor relationship: actor = Senior engineer profile, subject = Junior engineer profile, permissions = `{view, viewProgress}`.

**Historical data considerations.** Revoking a Relationship removes *future* visibility only — it must never delete or alter historical records the other party could previously see, and re-granting later must not retroactively resurrect the old access window (i.e., revocation is itself a dated fact, not a rewrite). A Relationship record itself is closer to configuration than history, but its `status` transitions (`pending → active → revoked`) should be timestamped and never overwritten, so "who could see what, when" stays answerable.

---

### 2.3 Goal

**Purpose.** The measurable outcome a person wants. Maps almost entirely onto the current `Goal` + `GoalAreaContribution` + `ResultMeasure` + `ResultEntry` cluster — this proposal keeps that cluster, and adds one optional link (§9) rather than restructuring it.

**Important fields.** `id`, `profile`, `name`, `purpose`, `targetDate`, `isActive` (unchanged from today). Its `ResultMeasure`(s) keep their existing typed-value model: `valueType` (number/rating/milestone/text), `direction` (increase/decrease/targetRange/maintainRange), `baselineValue`, `targetValue`/`targetMinimum`/`targetMaximum`, `cadence`. Its `ResultEntry`s keep their existing dated-evidence model.

**Change from current model (optional, additive).** A `ResultMeasure` may optionally carry `linkedMeasurementDefinitionID: UUID?` — when set, the Goal's progress can be *auto-derived* by summing matching `MeasurementEntry` records instead of requiring a manually-entered `ResultEntry` for every check-in. This is additive: existing manually-tracked Goals are unaffected, since the field defaults to unset.

**Relationships.** Belongs to one Profile. Supported by one or more Areas via `GoalAreaContribution` (unchanged). Optionally, a `ResultMeasure` links to one `MeasurementDefinition` for auto-rollup.

**Ownership.** Profile-owned.

**Examples.** "Improve Baseball Fielding" (primary Result: cumulative Ground Balls, linked to the Fielding Practice ActivityTemplate's `MeasurementDefinition`), "Improve System Design Skills" (primary Result: a manually-entered confidence rating, not auto-derived — some goals are evaluated by judgment, not tally), "Learn Guitar" (primary Result: songs completed, could be either manual or auto-derived depending on whether "Songs Completed" is tracked as a session measurement).

**Historical data considerations.** Unchanged from today: `ResultEntry` records are dated evidence and are never rewritten by later edits to the Goal's target or baseline. If a `ResultMeasure` is later unlinked from a `MeasurementDefinition`, previously auto-derived progress snapshots (if any were cached) must not silently change — auto-derived progress is a *live read*, not a stored fact, so this is naturally satisfied as long as progress is always computed on demand rather than persisted.

---

### 2.4 ActivityTemplate *(renamed from `Activity`)*

**Purpose.** The reusable definition of a repeatable action — generic across every domain, per the update doc's explicit rule against `BaseballActivity`/`MusicActivity` subclasses. Maps onto the current `Activity` model; the rename makes explicit what DESIGN.md already calls it in prose ("Task — the user-facing reusable definition... stored as `Activity` in Version 1").

**Important fields.** `id`, `profile`, `category` (Area), `name`, `source` (manual/template/aiSuggestion/imported), `tags`, `isActive`, `startDate`/`endDate` — all unchanged. Schedule fields (see §2.5) stay embedded here.

**Change from current model.** `targetValue: Double?` / `targetUnit: String?` — today's single fixed target — are proposed for replacement by a one-to-many relationship to `MeasurementDefinition`. See Open Question 1 for whether to keep a "primary simple target" convenience field for the casual-user case, or require even a single target to go through `MeasurementDefinition`.

**Relationships.** Belongs to one Profile, optionally one Area. Has one embedded `ScheduleRule`. Has zero or more `MeasurementDefinition`s. Produces many `CalendarItem`s (planned) and `ActivitySession`s (actual).

**Ownership.** Profile-owned via Area.

**Examples.** "Fielding Practice", "System Design Practice", "Guitar Practice" — identical shape regardless of domain; only the attached `MeasurementDefinition`s differ.

**Historical data considerations.** This is where the update doc's explicit requirement bites hardest: *"Historical sessions must keep their original measurement meaning even if the activity changes later."* Adding, renaming, retargeting, or removing a `MeasurementDefinition` on an ActivityTemplate must never change how an already-recorded `MeasurementEntry` is displayed or interpreted — solved by having `MeasurementEntry` snapshot its own name/type/unit at creation time (§2.8), the same pattern already designed (but not yet implemented, per the Step 6 stop) for `NutritionSnapshot`.

---

### 2.5 ScheduleRule

**Purpose.** Defines when an ActivityTemplate should produce planned occurrences. Today this is a set of fields embedded directly on `Activity` (`repeatType`, `weekdays`, `occurrencesPerDay`/`occurrencesPerWeek`, `repeatIntervalMinutes`, `plannedStartMinutes`, `estimatedDurationMinutes`) rather than a separate persisted entity, even though DESIGN.md's own diagram (`Activity → ScheduleRule → CalendarItem → ActivitySession`) already treats it as conceptually distinct.

**Proposal: keep it embedded, not a separate table**, for V2. Splitting it into its own entity would be pure schema churn with no behavior change unless a template needs *multiple concurrent schedules* — nothing in the three required examples (System Design Practice, Fielding Practice, Guitar Practice) needs that. Flagged as Open Question 2 in case product wants it anyway for future flexibility (e.g., "practice daily, but twice on weekends" as two rules instead of one `timesPerWeek` rule).

**Important fields (unchanged).** `repeatType` (once/daily/selectedWeekdays/timesPerDay/timesPerWeek), `weekdays`, `occurrencesPerDay`/`occurrencesPerWeek`, `repeatIntervalMinutes`, `plannedStartMinutes`, `estimatedDurationMinutes`, `startDate`/`endDate`.

**Relationships.** Belongs to (embedded in) exactly one ActivityTemplate. Drives `PlanningService.scheduledStartMinutes`, which generates `CalendarItem`s — this is the "one schedule engine" rule from DESIGN.md §22.3, unchanged.

**Ownership.** ActivityTemplate-owned.

**Examples.** "Daily at 7:00am for 45 minutes," "3×/week on Mon/Wed/Fri."

**Historical data considerations.** Unchanged from today's `reconcileUntouchedOccurrences` rule: editing a ScheduleRule may only remove *untouched, still-planned* future/current `CalendarItem`s that no longer match; anything decided (done/skipped) or historical is never touched. This rule is load-bearing and must carry forward exactly as-is.

---

### 2.6 ActivitySession

**Purpose.** What actually happened for one occurrence — the historical execution record. Today this is awkwardly split between `CalendarItem.actualStart`/`actualEnd`/`status` (completion-status side) and a separate `ActivitySession.recordedValue` (single-number evidence side, per DESIGN.md §10a). This proposal keeps both records — `CalendarItem` still owns planned-vs-actual *timing and status*; `ActivitySession` still owns *what was measured* — but generalizes the measurement side.

**Important fields.** `id`, `activityTemplate`, `profile`, `calendarItem` (optional — nil for unplanned/manual sessions, matching today's `AddWhatHappenedView` flow), `date`, `startedAt`, `endedAt`, `actualActiveSeconds`, `note` — all unchanged.

**Change from current model.** `recordedValue: Double` (today's single fixed number) is proposed for replacement by a one-to-many relationship to `MeasurementEntry`, mirroring the ActivityTemplate/MeasurementDefinition change above.

**Relationships.** Belongs to one ActivityTemplate and one Profile. Optionally references one `CalendarItem`. Has zero or more `MeasurementEntry` records.

**Ownership.** Profile-owned via ActivityTemplate.

**Examples.** "Fielding Practice session, Aug 12, 45 min → [100 Ground Balls, 40 Catches, Reaction Time 0.42s]."

**Historical data considerations.** An `ActivitySession` and its `MeasurementEntry`s are immutable historical fact except through explicit, user-initiated edit/delete (per DESIGN.md §4 Universal Editability — already implemented for `ActivitySession` this session, Refactor.md Step 5). Deleting the parent `ActivityTemplate` must not silently delete `ActivitySession`s — the existing nullify-relationship behavior (confirmed and relied on in Refactor.md Step 3's delete-vs-archive decision) is the model to preserve: an orphaned session with a snapshot of its own measurement names is still fully interpretable even if its ActivityTemplate is gone.

---

### 2.7 MeasurementDefinition

**Purpose.** A user-configurable "thing to track" attached to an ActivityTemplate — the *reusable definition* side of a measurement, per DESIGN.md's Core Domain Rule ("separate reusable definitions from actual historical records"). New entity.

**Important fields.**
- `id`, `activityTemplateID`
- `name` — user-typed, e.g. "Ground Balls," "Reaction Time," "Confidence"
- `type` — one of `count`, `duration`, `distance`, `percentage`, `rating`, `text`, `custom`
- `unit` — optional string; meaningful for count/duration/distance/percentage/custom (e.g. "reps," "seconds," "km," "%"), unused for rating/text
- `targetValue` — optional Double; meaningful for count/duration/distance/percentage/rating, absent for text/custom-without-a-number
- `isOptional` — Bool; an ActivityTemplate can have required and optional measurements side by side
- `sortOrder` — Int, for stable display order
- `isActive` — archive rather than hard-delete once any `MeasurementEntry` references it (mirrors the Activity delete-vs-archive rule from Refactor.md Step 3: archive when history exists, delete only when it doesn't)

**Relationships.** Belongs to one ActivityTemplate. Has zero or more `MeasurementEntry` records over time — but per §2.8, entries do not *require* this link to remain interpretable.

**Ownership.** ActivityTemplate-owned, transitively Profile-owned.

**Examples.**
- "Ground Balls" — count, unit "reps," target 100, required.
- "Reaction Time" — duration, unit "seconds," no fixed target, optional.
- "Confidence" — rating, 1–5 scale, no unit, optional.
- "Notes on technique" — text, no unit/target, optional.

**Historical data considerations.** Can be renamed, retargeted, reordered, archived, or (only if never used) deleted, without altering the meaning of any `MeasurementEntry` already recorded against it — because the entry snapshots its own descriptive fields at creation time (§2.8). This is the specific mechanism that satisfies "Historical sessions must keep their original measurement meaning even if the activity changes later."

---

### 2.8 MeasurementEntry

**Purpose.** The actual recorded value for one measurement within one ActivitySession — the *actual record* counterpart to MeasurementDefinition. New entity; this is the one the historical-integrity requirement centers on.

**Important fields.**
- `id`, `activitySessionID`
- `measurementDefinitionID` — **optional**, soft link for grouping/trend charts only, never required for correctness (see below)
- `nameSnapshot` — String, copied from the MeasurementDefinition at creation time
- `typeSnapshot` — same enum as MeasurementDefinition.type, copied at creation time
- `unitSnapshot` — String, copied at creation time
- `numericValue` — Double?, populated for count/duration/distance/percentage/rating
- `textValue` — String?, populated for text/custom-with-text
- `recordedAt` — Date

**Why the link is optional, not required.** If `MeasurementEntry` required a live foreign key to a `MeasurementDefinition` to be interpretable, deleting or renaming the definition would either be blocked forever (bad for a definition the user genuinely wants to clean up) or would corrupt history (worse). Snapshotting name/type/unit directly onto the entry means the definition can be freely edited, archived, or even deleted (once truly unused) without any historical entry losing meaning — the entry is self-describing. The optional link exists purely so trend charts/aggregation ("show Ground Balls over the last 8 weeks") have a fast, precise grouping key when the definition still exists; when it doesn't, grouping falls back to matching `nameSnapshot` (see Open Question 7).

**Relationships.** Belongs to one ActivitySession. Optionally references one MeasurementDefinition.

**Ownership.** ActivitySession-owned, transitively Profile-owned.

**Examples.**
- `{nameSnapshot: "Ground Balls", typeSnapshot: count, unitSnapshot: "reps", numericValue: 100}`
- `{nameSnapshot: "Reaction Time", typeSnapshot: duration, unitSnapshot: "sec", numericValue: 0.42}`
- `{nameSnapshot: "Confidence", typeSnapshot: rating, numericValue: 4}`
- `{nameSnapshot: "Technique notes", typeSnapshot: text, textValue: "Footwork improving, still rushing the throw"}`

**Historical data considerations.** Once recorded, a `MeasurementEntry`'s snapshot fields are never rewritten by definition changes. The entry itself remains user-correctable (edit/delete, per DESIGN.md §4) as an explicit, deliberate action — the same "correctable but not silently mutated" posture as every other historical record in the app.

---

### 2.9 Progress Calculation

Progress must support four modes without collapsing them into one blended score (consistent with the existing "no invented single Momentum score" rule):

**a) Simple completion tracking** — unchanged from today. `ProgressEngine.completionSummary`/`PeriodCompletionReport`: count of planned `CalendarItem`s done/skipped/missed/remaining. No measurements involved.

**b) Duration-based goals** — sum `ActivitySession.actualActiveSeconds` (or a `MeasurementEntry` of type `duration`, if duration is itself tracked as a named measurement rather than derived from session timing) over the goal's period, compared against a target duration.

**c) Single-measurement-based goals** — sum matching `MeasurementEntry.numericValue` (matched by `measurementDefinitionID`, falling back to `nameSnapshot` per Open Question 7) across all `ActivitySession`s for the ActivityTemplate, within the Goal's evaluation period, compared against `MeasurementDefinition.targetValue` × period-count or against the linked `ResultMeasure.targetValue` directly (see Open Question 3 for which one is authoritative).

**d) Multiple-measurement goals** — no single formula; see Open Question 4. This proposal does *not* invent an automatic weighting scheme. The existing "1 primary + up to 2 supporting `ResultMeasure`s" model already lets a Goal show several measurements' progress side by side without forcing them into one number — that model is proposed to remain the mechanism for multi-measurement goals, with each supporting `ResultMeasure` optionally auto-derived from a different `MeasurementDefinition`.

**Worked example (from the brief):**

```text
Goal: Improve Baseball Fielding
Target: 300 Ground Balls (cumulative, no expiry within the goal's window)

Sessions:
  Week 1 — Fielding Practice → MeasurementEntry(Ground Balls) = 100
  Week 2 — Fielding Practice → MeasurementEntry(Ground Balls) = 80
  Week 3 — Fielding Practice → MeasurementEntry(Ground Balls) = 120

current = sum of matching MeasurementEntry.numericValue = 100 + 80 + 120 = 300
target  = ResultMeasure.targetValue (or MeasurementDefinition.targetValue, if unlinked) = 300
progress = clamp(current / target, 0, 1) = 300 / 300 = 100%
```

This is exactly mode (c) above, and is a direct generalization of the `ProgressMetric.progress` computed property already implemented in Refactor.md Step 7 (`min(currentValue / targetValue, 1.0)`), with `currentValue` now able to come from a summed `MeasurementEntry` series instead of only `CompletionSummary.done` or `NutritionTotals.protein`. No new progress *formula* is needed — the generalization is entirely in what feeds `currentValue`.

---

## 3. Relationships (summary)

| From | To | Cardinality | Notes |
|---|---|---|---|
| Profile | Relationship | 1 → N (as either side) | Person ↔ Person, generic role via `relationshipType` |
| Profile | Area, Goal, ActivityTemplate | 1 → N | Unchanged from today |
| Goal | GoalAreaContribution → Area | N ↔ N | Unchanged |
| Goal | ResultMeasure | 1 → N (1 primary, ≤2 supporting) | Unchanged; `linkedMeasurementDefinitionID` is new and optional |
| ActivityTemplate | ScheduleRule | 1 → 1 (embedded) | Unchanged, proposed to stay embedded |
| ActivityTemplate | MeasurementDefinition | 1 → N | New |
| ActivityTemplate | CalendarItem | 1 → N | Unchanged |
| ActivityTemplate | ActivitySession | 1 → N | Unchanged |
| CalendarItem | ActivitySession | 1 → 0..1 (optional) | Unchanged — a session may exist without a planned item (manual/unplanned entry) |
| ActivitySession | MeasurementEntry | 1 → N | New, replaces single `recordedValue` |
| MeasurementDefinition | MeasurementEntry | 1 → N (soft link) | New; link is optional, entry is self-describing via snapshot fields |

---

## 4. Example Flows

### 4.1 Self-improvement

```text
Person:            Developer
Goal:               Improve System Design Skills
  ResultMeasure:     Confidence (rating, 1–5), manually entered — judgment-based, not auto-derived
ActivityTemplate:   System Design Practice
  ScheduleRule:      3×/week, 45 min
  MeasurementDefinitions:
    - Study duration   (duration, minutes, target 45, required)
    - Topics completed (count, topics, no fixed target, optional)
    - Confidence       (rating, 1–5, optional — session-level self-check, separate from the Goal's own check-in)

Session (Tuesday):
  ActivitySession → MeasurementEntry(Study duration = 50 min),
                    MeasurementEntry(Topics completed = 2)

Progress:
  Duration-based: 50 / 45 for that session (per-session, capped at 100% for scoring, real number always shown)
  Goal's Confidence ResultMeasure: still evidence entered on the Goal's own cadence (e.g. monthly), not derived from these sessions
```

### 4.2 Sports

```text
Person:            Player
Goal:               Improve Baseball Fielding
  ResultMeasure:     Ground Balls (count), linked to the Ground Balls MeasurementDefinition, target 300, auto-derived
ActivityTemplate:   Fielding Practice
  ScheduleRule:      Daily, 30 min
  MeasurementDefinitions:
    - Ground Balls     (count, reps, target 100/session, required)
    - Fly Balls        (count, reps, optional)
    - Catches           (count, reps, optional)
    - Reaction Time     (duration, seconds, optional)
    - Throw Accuracy    (percentage, %, optional)

Three sessions → MeasurementEntry(Ground Balls) = 100, 80, 120
Goal progress (§2.9c): 300 / 300 = 100%
```

### 4.3 Learning

```text
Person:            Student
Goal:               Learn Guitar
  ResultMeasure:     Songs completed (count), linked, target 10, auto-derived
ActivityTemplate:   Guitar Practice
  ScheduleRule:      Daily, 20 min
  MeasurementDefinitions:
    - Practice duration (duration, minutes, required)
    - Songs completed    (count, songs, optional — logged only on sessions where a song was finished)
    - Chords learned     (count, chords, optional)

Progress: sum of Songs completed MeasurementEntry values across sessions, vs. target 10
```

---

## 5. Migration Impact Analysis

| Current model | Proposed V2 | Change type | Risk |
|---|---|---|---|
| `Profile` | `Profile` (unchanged fields) | None required now | **None.** `Relationship` is additive; removing `ProfileKind`/`ProfileManagementMode` is a separate, later decision (Open Question 5), not required to ship the rest of this proposal. |
| `Activity` | `ActivityTemplate` | Rename (cosmetic) + remove `targetValue`/`targetUnit`, add `MeasurementDefinition[]` | **Medium–High.** The rename alone is free. Removing the single target field is structural: every existing `Activity.targetValue`/`targetUnit` must migrate into an equivalent `MeasurementDefinition` (one auto-created per existing activity that has a target) so no existing target silently disappears. |
| `CalendarItem` | `CalendarItem` (unchanged) | None | **None.** |
| `ActivitySession` | `ActivitySession` (minus `recordedValue`, plus `MeasurementEntry[]`) | Structural | **Medium.** Same shape of change as Activity above: every existing `ActivitySession.recordedValue` must migrate into one `MeasurementEntry` snapshotting the parent Activity's (pre-migration) `targetUnit` as its name/unit, so historical session values keep their meaning. |
| `Goal` | `Goal` (unchanged) | None | **None.** |
| `ResultMeasure` | `ResultMeasure` + optional `linkedMeasurementDefinitionID` | Additive | **Low.** New optional field, defaults unset, no existing data affected. |
| `ResultEntry` | `ResultEntry` (unchanged) | None | **None.** |
| — | `Relationship` (new) | New entity | **Low.** Purely additive; no existing data to migrate. Risk is entirely in getting the permission model right *before* people start depending on it, not in the migration itself. |
| — | `MeasurementDefinition` (new) | New entity | **Low** as a table; **Medium** as part of the Activity migration above (must be populated correctly during that migration, not created empty). |
| — | `MeasurementEntry` (new) | New entity | **Low** as a table; **Medium** as part of the ActivitySession migration above, for the same reason. |

**Overall assessment:** the two genuinely risky migrations — `Activity.targetValue` → `MeasurementDefinition`, and `ActivitySession.recordedValue` → `MeasurementEntry` — are the same class of risk Refactor.md Step 6 already stopped on for Nutrition (FoodEntry → FoodDefinition/FoodLogEntry). Both need: (1) the V1 types preserved immutably per `SchemaVersioning.swift`'s documented process, (2) a real V1-store data fixture to test the migration against before it ships, and (3) explicit sign-off on the backfill rule (§ migration mapping: one `MeasurementDefinition`/`MeasurementEntry` auto-created per existing scalar target/value, named after the existing `targetUnit` string). Nothing else in this proposal requires a data migration at all.

---

## 6. Open Questions Requiring Product Decisions

1. **Keep a "simple primary target" convenience field on ActivityTemplate, or require even a single target to go through MeasurementDefinition?** Affects casual-user simplicity (per the update doc's progressive-tracking philosophy — "Level 1" users just want completion + duration, no measurement configuration UI at all) vs. schema uniformity. A plausible middle ground: every ActivityTemplate can have **zero** MeasurementDefinitions and still work fine (pure completion tracking), so this may be a non-issue — worth confirming.
2. **Should ScheduleRule become its own persisted entity**, enabling multiple concurrent schedules per ActivityTemplate, or stay embedded as today? Nothing in the three required examples needs it; only worth the schema churn if a real use case (e.g., "daily, but twice on weekends") is prioritized.
3. **Should Goal progress auto-compute from summed MeasurementEntries, stay purely manual ResultEntry check-ins, or support both** (manual entry as an explicit override of an auto-computed value)? This is the single biggest product-behavior decision in this proposal — it changes what "entering a Goal result" means for measurement-backed goals.
4. **How does a multi-measurement Goal combine progress** when it cares about more than one MeasurementDefinition (e.g., both Ground Balls *and* Catches matter for "fielding improvement")? This proposal defaults to "don't combine — show each as its own supporting ResultMeasure," per the existing no-blended-score philosophy. Confirm that's the intended behavior rather than a weighted composite.
5. **Relationship model scope for V1 of this entity.** Minimum viable permission set (view/edit/manageActivities/receiveNotifications/viewProgress as proposed, or fewer)? Does granting a Relationship require two-device mutual consent (the deferred Family Sync capability from DESIGN.md §25.6), or can a single-device "this Adult profile manages this Child profile on this phone" case skip consent entirely, since it's already true locally today via `ProfileManagementMode`? Getting this scoped correctly determines whether `ProfileKind`/`ProfileManagementMode` can be retired now or must coexist with `Relationship` for a while.
6. **Should Nutrition V2 (FoodDefinition/FoodLogEntry/NutritionSnapshot, stopped at Refactor.md Step 6) reuse this same MeasurementDefinition/MeasurementEntry engine, or remain its own typed domain**, per DESIGN.md §6/§13's explicit non-goal ("do not create one giant generic model... use typed domain models")? This determines whether the two migrations should be planned and executed together or fully independently.
7. **MeasurementEntry aggregation when the MeasurementDefinition link is absent** (definition deleted, or entry predates the definition existing in its current form) — fall back to exact `nameSnapshot` string match, fuzzy match, or simply exclude unlinked entries from trend charts (still showing them in raw session history, just not in aggregated views)? Affects how forgiving trend charts are to renamed/recreated measurements.

---

**Stopping here per instruction.** No code, no SwiftData model changes, no migration plan implementation — this document is the design proposal only, awaiting review and decisions on the open questions above before any implementation phase is agreed.
