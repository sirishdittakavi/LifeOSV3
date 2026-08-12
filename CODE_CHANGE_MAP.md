# LifeOS — Code Change Map (V2)

**Status:** Analysis and documentation only. No code modified, no migrations created, nothing implemented.
**Source of truth:** `Architecture.md`, `Refactor.md`, `DOMAIN_MODEL_V2_PROPOSAL.md`, `IMPLEMENTATION_PHASE_PLAN_V2.md`.
**Method:** Every file listed below was located via `grep -rn "targetValue\|targetUnit\|recordedValue"` across `LifeOS`, `LifeOSUnitTests`, `LifeOSComponentTests`, then individually re-checked to confirm which model each hit actually belongs to — `ResultMeasure.targetValue` (Goal evidence, unrelated to this migration) and `Activity.targetValue`/`ActivitySession.recordedValue` (the old single-metric model, the actual subject of this migration) share field names but are different fields on different models. Hits are attributed correctly below; several files below were initially assumed relevant and turned out not to be (noted explicitly where that happened, since a wrong assumption here is exactly the kind of thing that turns Phase 4 into a half-finished migration).

---

## 1. Current Architecture File Map

```text
Models/Models.swift          — all @Model classes (Profile, AppCategory, Goal, GoalAreaContribution,
                                 ResultMeasure, ResultEntry, Activity, CalendarItem, ActivitySession,
                                 FoodEntry, WeightEntry, SportEntry)
Models/SchemaVersioning.swift — LifeOSSchemaV1, LifeOSMigrationPlan, LifeOSDataStore
Models/SeedData.swift        — first-run seed content (constructs Activity with targetValue/targetUnit)

Engine/PlanningService.swift        — schedule engine, occurrence reconstruction, CalendarItem generation
Engine/ProgressEngine.swift         — DailyActivityProgress, CompletionSummary, PeriodCompletionReport,
                                        NutritionTotals, completionSummary/dailyProgress/periodCompletionReport
Engine/CategoryProgressEngine.swift — CategoryProgress + GoalProgressEngine (Goal outcome/effort comparison)
Engine/ProgressMetric.swift         — generic ProgressMetric type + ProgressMetricBuilder (Step 7)
Engine/CalendarRepository.swift     — Today's persistence boundary (Step 4)
Engine/TodayViewModel.swift         — Today's derived state + actions (Step 4)
Engine/CategoryHierarchy.swift      — Area tree traversal
Engine/ImprovementTemplates.swift   — starter Area/Activity templates (constructs Activity w/ targetValue)
Engine/LifeOSBackupService.swift    — full-family JSON backup/restore (encodes Activity/ActivitySession)
Engine/PortableMetricService.swift  — portable JSON metric contract (encodes Activity/ActivitySession)
Engine/ReminderService.swift        — local notification scheduling (excluded from SPM package)
Engine/PersistenceSupport.swift     — ModelContext.saveOrReport, PersistenceIssueCenter, ProfileScope

Views/TodayTimelineView.swift       — Today screen (uses TodayViewModel)
Views/WeeklyScheduleView.swift      — Week screen
Views/AddActivityView.swift         — create Activity (has the single target field UI)
Views/EditTaskView.swift            — edit/delete/archive Activity (Step 3), has the target field UI
Views/RecordActualView.swift        — "Done" flow — records ActivitySession.recordedValue against a CalendarItem
Views/AddWhatHappenedView.swift     — manual/unplanned Activity + CalendarItem + ActivitySession creation
Views/DailyProgressView.swift       — Section 10a target-vs-actual display + ActivitySessionHistoryView (Step 5)
Views/ImprovementDashboardView.swift — Goals dashboard (ResultMeasure-heavy, not Activity-target-heavy)
Views/EditGoalViews.swift           — Goal/ResultMeasure create/edit (ResultMeasure-heavy)
Views/ImprovementCategoryDetailView.swift — Area detail, Category progress
Views/ProfileManagerView.swift      — Profile create/edit/hide (ProfileKind/ManagementMode live here)
Views/RootTabView.swift             — onboarding starter-plan Activity creation
Views/FoodTrackerView.swift / WeightTrackerView.swift / SportTrackerView.swift — nutrition/weight/sport (Step 5, unrelated to this migration)
LifeOSApp.swift                     — sample/preview data construction

LifeOSUnitTests/TestFixtures.swift, PlanningServiceTests.swift, ProgressAndHierarchyTests.swift,
  TodayViewModelTests.swift, PortableMetricServiceTests.swift
LifeOSComponentTests/GoalSystemComponentTests.swift
```

---

## 2. Models

### 2.1 `Profile`

- **Current responsibility.** The person whose life LifeOS tracks. Owns Areas/Goals/Activities/Sessions.
- **Current model/logic used.** `kindRaw`/`kind: ProfileKind` (adult/child/individual), `managementModeRaw`/`managementMode: ProfileManagementMode` (parentManaged/selfManaged), plus nutrition/weight preference fields.
- **Expected V2 change.** No field changes required. `Relationship` (new, §2.4 below) is additive alongside it. `ProfileKind`/`ProfileManagementMode` are explicitly **not removed** by this plan (Phase Plan §7: "no urgency to retire them... left out of this plan entirely rather than deferred-and-tracked").
- **Which phase changes it.** None directly (Phase 7 adds `Relationship` UI elsewhere, doesn't touch `Profile` itself).
- **Tests affected.** None.
- **Risk level.** None.

### 2.2 `Activity` *(→ conceptually `ActivityTemplate` per the proposal; class name change is optional, see Open Question in §6)*

- **Current responsibility.** Reusable definition of a repeatable action: name, category, schedule fields, source, and the single `targetValue`/`targetUnit` pair.
- **Current model/logic used.** `targetValue: Double?`, `targetUnit: String?` — one fixed numeric target per Activity. Everything else (schedule fields, `isActive`, `source`) is unrelated to this migration and unchanged.
- **Expected V2 change.** Remove `targetValue`/`targetUnit` (Phase 5). Add a to-many relationship to `MeasurementDefinition` (Phase 1). Between Phase 1 and Phase 5, both exist simultaneously (Phase 3's intentional additive window).
- **Which phase changes it.** Phase 1 (add relationship to `MeasurementDefinition`), Phase 5 (remove `targetValue`/`targetUnit`).
- **Tests affected.** Every test that constructs `Activity(targetValue:targetUnit:...)` — see §5.
- **Risk level.** Medium (field removal touches many call sites; see §4).

### 2.3 `ActivitySession`

- **Current responsibility.** What actually happened for one occurrence: timing (`startedAt`/`endedAt`/`actualActiveSeconds`) plus one `recordedValue: Double`.
- **Current model/logic used.** `recordedValue: Double` — one fixed number per session.
- **Expected V2 change.** Remove `recordedValue` (Phase 5). Add a to-many relationship to `MeasurementEntry` (Phase 1).
- **Which phase changes it.** Phase 1, Phase 5.
- **Tests affected.** Every test constructing `ActivitySession(recordedValue:...)` — see §5.
- **Risk level.** Medium (same class as `Activity`, smaller blast radius since fewer call sites read it than `Activity.targetValue`).

### 2.4 `Relationship` *(new)*

- **Current responsibility.** N/A — does not exist today.
- **Expected V2 shape.** Per `DOMAIN_MODEL_V2_PROPOSAL.md` §2.2: `id`, `subjectProfileID`, `actorProfileID`, `relationshipType: String`, `permissions: Set<...>`, `status`, `createdAt`/`respondedAt`.
- **Which phase adds it.** Phase 1 (model), Phase 2 (repository), Phase 7 (UI).
- **Tests affected.** None existing; new tests required (§5).
- **Risk level.** None (purely additive).

### 2.5 `MeasurementDefinition` *(new)*

- **Current responsibility.** N/A.
- **Expected V2 shape.** Per proposal §2.7: `id`, `activityTemplateID`, `name`, `type` (count/duration/distance/percentage/rating/text/custom), `unit`, `targetValue`, `isOptional`, `sortOrder`, `isActive`.
- **Which phase adds it.** Phase 1 (model), Phase 2 (repository + aggregation), Phase 3 (UI to create/edit).
- **Tests affected.** None existing; new tests required.
- **Risk level.** None at creation (Phase 1); becomes load-bearing once Phase 4/5 route through it.

### 2.6 `MeasurementEntry` *(new)*

- **Current responsibility.** N/A.
- **Expected V2 shape.** Per proposal §2.8: `id`, `activitySessionID`, `measurementDefinitionID` (optional), `nameSnapshot`, `typeSnapshot`, `unitSnapshot`, `numericValue`, `textValue`, `recordedAt`.
- **Which phase adds it.** Phase 1, 2, 3.
- **Tests affected.** None existing; new tests required.
- **Risk level.** None at creation; load-bearing once Phase 4/5 land.

### 2.7 `Goal`, `GoalAreaContribution`, `ResultMeasure`, `ResultEntry`

- **Current responsibility.** Measurable outcome + supporting Areas + typed evidence + dated check-ins. **Not** part of the `targetValue`/`recordedValue` migration — `ResultMeasure.targetValue`/`baselineValue` are a separate field on a separate model, evaluated independently by `GoalProgressEngine`.
- **Expected V2 change.** Only `ResultMeasure` changes, and only additively: optional `linkedMeasurementDefinitionID: UUID?` (Phase 6). `Goal`, `GoalAreaContribution`, `ResultEntry` are untouched by this entire plan.
- **Which phase changes it.** Phase 6 (`ResultMeasure` only).
- **Tests affected.** New `GoalProgressEngine` tests for the auto-rollup path (Phase 6); zero existing Goal tests need changes, since the new field defaults nil and is purely additive.
- **Risk level.** None for `Goal`/`GoalAreaContribution`/`ResultEntry`. Low for `ResultMeasure`'s new field.

---

## 3. Engine Layer

### 3.1 `ProgressEngine.swift`

- **Current responsibility.** `DailyActivityProgress` (target-vs-actual per Section 10a), `CompletionSummary`, `PeriodCompletionReport`, `NutritionTotals`.
- **Current model/logic used.** `DailyActivityProgress.target` reads `activity.targetValue` directly (line 21). `dailyProgress(...)` filters `activities` by `$0.targetValue != nil` (line 135) and sums `daySessions.reduce(0.0) { $0 + $1.recordedValue }` (line 142).
- **Expected V2 change.** `DailyActivityProgress.target` and the `dailyProgress` filter/sum move to reading `MeasurementDefinition`/`MeasurementEntry` instead — this becomes (or is superseded by) the aggregation function `IMPLEMENTATION_PHASE_PLAN_V2.md` Phase 2 specifies. `CompletionSummary`/`PeriodCompletionReport`/`NutritionTotals` are **not** part of this migration (no target/recordedValue involvement) and stay exactly as-is — this file is only *partly* affected, not wholesale rewritten.
- **Which phase changes it.** Phase 2 (add the new aggregation function), Phase 4 (repoint `DailyActivityProgress`/`dailyProgress` at it).
- **Tests affected.** `ProgressAndHierarchyTests.testDailyProgressSumsOnlySelectedProfileAndDay` (constructs `Activity(targetValue:...)` and `ActivitySession(recordedValue:...)` directly — needs rewriting to the new model, not just field renames, since the aggregation source changes).
- **Risk level.** Medium — this is the single most-depended-on function for Today's Plan cards and `DailyProgressView`.

### 3.2 `CategoryProgressEngine.swift`

- **Current responsibility.** `CategoryProgress` (Area-level progress) and `GoalProgressEngine` (Goal outcome/effort).
- **Current model/logic used.** **Verified: every `targetValue` reference in this file (lines 356, 426, 432, 436, 461, 467, 471) is `measure.targetValue` — `ResultMeasure`, not `Activity`.** This file does not read `Activity.targetValue` or `ActivitySession.recordedValue` anywhere.
- **Expected V2 change.** **None**, for the target/recordedValue migration specifically. This file was a candidate in an earlier draft of the phase plan and is explicitly ruled out here after verification — including it in Phase 4 would have been scope creep.
- **Which phase changes it.** Phase 6 only, for the optional `linkedMeasurementDefinitionID` auto-rollup addition to `GoalProgressEngine.progress` — unrelated to the target/recordedValue migration.
- **Tests affected.** None from Phase 4/5. New focused tests from Phase 6.
- **Risk level.** None from this migration.

### 3.3 `ProgressMetric.swift`

- **Current responsibility.** Generic `title/currentValue/targetValue/unit/statusText/destination` type + builders wrapping `CategoryProgress`/`GoalProgress`/`DailyActivityProgress`/`NutritionTotals`.
- **Current model/logic used.** `ProgressMetric.targetValue` is its **own** field (unrelated to Activity's). `ProgressMetricBuilder.metric(from: DailyActivityProgress)` reads `progress.target` and `progress.activity.targetUnit` (lines 69–70) — this is an *indirect* dependency: once `DailyActivityProgress.target` (§3.1) is repointed at the new model, this builder needs zero changes itself, since it just reads `.target`/`.activity.targetUnit`, both of which keep existing as computed properties even after Phase 4/5 (the properties survive; only their internal implementation changes).
- **Expected V2 change.** None directly, contingent on `DailyActivityProgress` (§3.1) preserving its `.target`/property shape through the migration. `TodayTimelineView`'s `taskMetric`/nutrition-metric construction (lines 343–379) uses `ProgressMetric`'s own fields and `NutritionTotals` — both untouched by this migration.
- **Which phase changes it.** None directly; verify as part of Phase 4's build check.
- **Tests affected.** `ProgressAndHierarchyTests.testProgressMetricBuilderWrapsCategoryAndGoalProgressGenerically` doesn't cover the `DailyActivityProgress` builder — consider adding coverage in Phase 4 so this indirect dependency has an explicit test, not just an implicit one.
- **Risk level.** Low, but worth an explicit test per above rather than relying on "it happens to still compile."

### 3.4 `CalendarRepository.swift` / `TodayViewModel.swift`

- **Current responsibility.** Today's persistence boundary and derived-state/actions (Step 4).
- **Current model/logic used.** `CalendarItem`, `Activity` (for schedule generation) — no `targetValue`/`recordedValue` usage in either file (verified: not in the grep hit list).
- **Expected V2 change.** None.
- **Which phase changes it.** None.
- **Tests affected.** None.
- **Risk level.** None.

### 3.5 `MeasurementRepository.swift` *(new)* / `RelationshipRepository.swift` *(new)*

- **Current responsibility.** N/A — don't exist yet.
- **Expected V2 shape.** Protocol + SwiftData implementation mirroring `CalendarRepository`'s shape (Phase Plan Phase 2).
- **Which phase changes it.** Phase 2 (create), Phase 7 (`RelationshipRepository` consumed by Relationship UI).
- **Tests affected.** None existing; new fake-repository-backed tests required, mirroring `FakeCalendarRepository`/`TodayViewModelTests` pattern.
- **Risk level.** None (new, additive, no existing call sites).

### 3.6 `ImprovementTemplates.swift`

- **Current responsibility.** Starter Area/Activity template blueprints used by onboarding and "Use a Template."
- **Current model/logic used.** `AreaTemplateAction`-style blueprint struct carries `targetValue: Double?`/`targetUnit: String?` (lines 10–11, 20, 29–30, 195, 223, 228, 253–254), passed straight into `Activity(...)` construction.
- **Expected V2 change.** Blueprint's target fields either map to an auto-created `MeasurementDefinition` at template-apply time, or the blueprint format itself gains a `measurements: [MeasurementDefinitionBlueprint]` shape. This is a design decision, not just a mechanical field swap (see §6).
- **Which phase changes it.** Phase 4.
- **Tests affected.** Any template-application test asserting on the resulting Activity's target (check `ProgressAndHierarchyTests.testStarterTemplatesRemainCompleteEditableStartingPoints` — confirm at implementation time whether it asserts target values).
- **Risk level.** Medium — template blueprints are static seed data touched by onboarding, a first-run-critical path.

### 3.7 `LifeOSBackupService.swift`

- **Current responsibility.** Full-family JSON backup/restore.
- **Current model/logic used.** Backup record structs mirror the models being backed up: line 50 (`targetValue` in a `ResultMeasure`-shaped record — **not** in scope), line 63 (`targetValue`/`targetUnit` in an `Activity`-shaped record — **in scope**), line 78 (`recordedValue` in an `ActivitySession`-shaped record — **in scope**). Encode sites: 151 (ResultMeasure, not in scope), 165–166 (Activity, in scope), 181 (ActivitySession, in scope). Decode/apply sites: 291 (ResultMeasure, not in scope), 321–322 (Activity, in scope), 349 (ActivitySession, in scope).
- **Expected V2 change.** The Activity/ActivitySession backup record shapes need new fields for `MeasurementDefinition`/`MeasurementEntry` arrays, and (post-Phase-5) lose `targetValue`/`targetUnit`/`recordedValue`. Backup schema versioning (`schemaVersion` field already exists in this file, per DESIGN.md §25.4 "Schema 2 writes the Goal system") needs a new schema bump for this change, distinct from `SchemaVersioning.swift`'s SwiftData versioning — **this is its own migration surface** and should not be conflated with the SwiftData-store migration decision in Phase Plan §0.
- **Which phase changes it.** Phase 4 (add new fields, keep old readable for restore-from-old-backup during the transition), Phase 5 (stop writing old fields).
- **Tests affected.** `GoalSystemComponentTests` backup/restore round-trip tests (`testSchemaTwoBackupRoundTripRestoresCompleteGoalGraphWithoutDuplicates`, `testDamagedBackupIsRejectedBeforeItCanMutateTheStore`, `testVersionOnePlanOpensAStoreCreatedBeforeExplicitVersioning`) — these specifically test schema compatibility and must be re-verified, not just recompiled.
- **Risk level.** **Medium-high.** This is the one place where "no real users" doesn't fully eliminate migration risk — a developer's own exported backup file (if any exist from testing) becomes unrestorable across this change unless explicitly handled, and the backup format's own versioning discipline (already established, real, and tested) should be respected even though the underlying SwiftData store's versioning discipline is being relaxed per Phase Plan §0.

### 3.8 `PortableMetricService.swift`

- **Current responsibility.** Versioned JSON event-envelope export (Android/analytics/integration contract, DESIGN.md §14.1).
- **Current model/logic used.** Line 233 (`session.recordedValue`, in scope), 236–237 (`activity?.targetValue`/`targetUnit`, in scope), 262 (`measure?.targetValue`, **not** in scope — ResultMeasure).
- **Expected V2 change.** The exported `action_session` event's fields need to represent one-or-many measurements instead of one `recorded_value`/`target_value`/`unit` triple. DESIGN.md §14.1 explicitly states this contract "must not reduce all values to strings" and uses "an explicit `{ type, value }` representation" — the existing typed-field design already anticipates something like this; extending it to an array of `{name, type, value, unit}` is a natural fit, but is itself a contract version bump (the file's own `schemaVersion`/`PortableMetricEnvelope` versioning, again distinct from the SwiftData question).
- **Which phase changes it.** Phase 4.
- **Tests affected.** `PortableMetricServiceTests.testEveryVersionOneEvidenceTypeMapsToPortableMetrics`, `testPortableJSONRoundTripPreservesTypedFlexibleFields`, `testFutureSchemaAndInvalidNumbersAreRejected` — all construct `Activity`/`ActivitySession` with the old fields and assert on the exported shape; need rewriting, not just recompiling.
- **Risk level.** Medium — external contract surface (DESIGN.md explicitly designed this for Android/analytics consumers), so changing its shape is a compatibility decision even though the SwiftData store itself has no compatibility obligation.

---

## 4. Views

### 4.1 `AddActivityView.swift`

- **Current responsibility.** Create a new `Activity`, including the single target field.
- **Current model/logic used.** `@State targetValue`/`targetUnit` (lines 27–28), text fields (140, 144), passed into `Activity(targetValue:targetUnit:...)` (318–319).
- **Expected V2 change.** Replace the single target field with a "Measurements" section (create one or more `MeasurementDefinition`s) — additive in Phase 3 (old field still present), field removed in Phase 5.
- **Which phase changes it.** Phase 3 (add), Phase 5 (remove old field UI).
- **Tests affected.** None directly (no unit tests exercise this View; it's UI-only, consistent with how Refactor.md Step 5 already established View-level CRUD isn't unit-tested in this codebase).
- **Risk level.** Low technically, **high in user-facing terms** — this is "Create activities/tasks," one of the six must-keep-working features (Phase Plan §0). Manual verification required, not just a build check.

### 4.2 `EditTaskView.swift`

- **Current responsibility.** Edit/delete/archive an `Activity` (Step 3's `hasHistory`-gated delete-vs-archive logic lives here too).
- **Current model/logic used.** `@State targetValue`/`targetUnit` (22–23), initialized from `activity.targetValue`/`targetUnit` (44–46), written back on save (272–273), displayed in `TaskDetailView`'s detail rows (445–446).
- **Expected V2 change.** Same as `AddActivityView` — add Measurements management UI (Phase 3), remove old field UI (Phase 5). **Note: `hasHistory`/`deleteOrArchive` (Step 3) must be re-verified against the new model** — `PlanningService.hasAnyHistory` currently only inspects `CalendarItem`s; once sessions carry `MeasurementEntry` arrays instead of a scalar, the delete-safety logic itself doesn't change (it was never based on `recordedValue` in the first place), but this should be explicitly re-confirmed, not assumed, since it's exactly the kind of cross-feature interaction a migration can silently break.
- **Which phase changes it.** Phase 3, Phase 5.
- **Tests affected.** None directly (UI-only). `PlanningServiceTests`' `hasAnyHistory`-related tests (`testHasAnyHistoryDistinguishesUntouchedPlansFromRealRecords`) don't reference `targetValue`/`recordedValue` and should be unaffected — confirm this remains true after Phase 5.
- **Risk level.** Medium — touches Step 3's delete-safety logic by proximity, even if not by direct field dependency.

### 4.3 `RecordActualView.swift`

- **Current responsibility.** The "Done"/"Finish" completion flow — records an `ActivitySession` against a `CalendarItem`, using the Activity's target to drive a Stepper UI.
- **Current model/logic used.** Heaviest single-view dependency on the old model: `_recordedValue` initialized from `item.activity?.targetValue` (25), `hasTarget` computed from `item.activity?.targetValue != nil` (30), Stepper bounded by `target * 3` (50–52), `ActivitySession(recordedValue:...)` construction (104). Line 120 is a `#Preview`/test-fixture construction, not production logic.
- **Expected V2 change.** When the Activity has `MeasurementDefinition`s, show one Stepper/field per definition instead of one scalar Stepper; each becomes a `MeasurementEntry`. This is the most **user-facing-behavior-sensitive** file in the whole migration — it's literally "Activity completion flow," must-keep-working feature #5.
- **Which phase changes it.** Phase 3 (add multi-measurement recording, old scalar flow still present for Activities without `MeasurementDefinition`s), Phase 4/5 (old scalar flow fully replaced).
- **Tests affected.** None directly (UI-only); manual verification is the actual safety net here, explicitly.
- **Risk level.** **High**, user-facing — this is the single view where a broken migration would be most immediately visible to a user tapping "Done."

### 4.4 `AddWhatHappenedView.swift`

- **Current responsibility.** Manual/unplanned entry — creates an `Activity` + `CalendarItem` + `ActivitySession` together in one save.
- **Current model/logic used.** `recordedValue` state (26), `Activity(targetValue: hasValue ? recordedValue : nil, targetUnit: hasValue ? unit : nil, ...)` (119–120), `ActivitySession(recordedValue:...)` (145).
- **Expected V2 change.** Same pattern as `RecordActualView` — replace the single value field with measurement recording, and the created `Activity` gets a `MeasurementDefinition` instead of `targetValue`/`targetUnit` if `saveAsReusable` is set.
- **Which phase changes it.** Phase 4 (this view doesn't have an "additive Phase 3" easy path the way Add/Edit do, since it constructs everything in one shot — worth flagging as needing its own care, not just a copy of the `RecordActualView` approach).
- **Tests affected.** None directly (UI-only).
- **Risk level.** Medium-high — same class of risk as `RecordActualView`, slightly lower usage frequency (unplanned entries are rarer than scheduled completions).

### 4.5 `DailyProgressView.swift`

- **Current responsibility.** DESIGN.md Section 10a target-vs-actual display, plus `ActivitySessionHistoryView`/`EditActivitySessionView` (Step 5's session edit/delete UI).
- **Current model/logic used.** `ProgressBarRow` reads `progress.target`/`progress.activity.targetUnit` (via `DailyActivityProgress`, §3.1). `TrendRow.fraction(for:)` reads `activity.targetValue` directly (229) and sums `session.recordedValue` (232). `ActivitySessionHistoryView` displays `session.recordedValue`/`activity.targetUnit` (116). `EditActivitySessionView` edits `session.recordedValue` directly (142, 149, 158, 184) — **this is Step 5's new session-editing feature, built this session, now itself squarely in the migration's path.**
- **Expected V2 change.** `TrendRow` needs to sum matching `MeasurementEntry` values instead of `recordedValue`. `EditActivitySessionView` needs to edit a session's `MeasurementEntry` list instead of one scalar field — a real UI change to a feature that's barely a day old.
- **Which phase changes it.** Phase 4.
- **Tests affected.** None directly (UI-only).
- **Risk level.** Medium-high — this view has the most call sites of any single View file, and directly touches the Step 5 work.

### 4.6 `TodayTimelineView.swift`

- **Current responsibility.** Today screen — Plan cards, active/decided item lists, via `TodayViewModel`.
- **Current model/logic used.** Lines 343, 354, 374, 379 are `ProgressMetric`'s own `targetValue` field (unrelated — Step 7 infrastructure). Lines 939–940 (`item.activity?.targetValue`/`targetUnit`) are genuinely Activity-target-dependent — used for `completionText`, the caption shown on a completed item (verify exact purpose at implementation time; likely "80/100 swings" style summary text).
- **Expected V2 change.** Only lines 939–940's `completionText` computation needs updating, to read the session's `MeasurementEntry` values instead. The Plan-card `ProgressMetric` usage (343–379) is untouched — already confirmed independent in §3.3.
- **Which phase changes it.** Phase 4 (small, isolated change — one function).
- **Tests affected.** None directly.
- **Risk level.** Low — small, isolated surface within an otherwise-untouched file; the "Today view" must-keep-working feature is much more dependent on `TodayViewModel`/`CalendarRepository` (untouched) than on this one caption function.

### 4.7 `WeeklyScheduleView.swift`

- **Current responsibility.** Week screen.
- **Current model/logic used.** No `targetValue`/`targetUnit`/`recordedValue` usage (not in the grep hit list — verified absent).
- **Expected V2 change.** None.
- **Which phase changes it.** None.
- **Tests affected.** None.
- **Risk level.** None. This is exactly the confirmation the "Week calendar view" must-keep-working feature needs — it structurally cannot regress from this migration since it never touched the fields involved.

### 4.8 Goal views (`ImprovementDashboardView.swift`, `EditGoalViews.swift`)

- **Current responsibility.** Goals dashboard, Goal/ResultMeasure create/edit.
- **Current model/logic used.** **Verified: every `targetValue` hit in both files is `measure.targetValue` — `ResultMeasure`, not `Activity`.** Not part of the target/recordedValue migration.
- **Expected V2 change.** Only Phase 6's `linkedMeasurementDefinitionID` UI addition to `EditGoalViews.swift` (linking a `ResultMeasure` to a `MeasurementDefinition`) — everything else in both files is untouched.
- **Which phase changes it.** Phase 6 (`EditGoalViews.swift` only).
- **Tests affected.** New Phase 6 tests only.
- **Risk level.** None from Phase 4/5. Low from Phase 6.

### 4.9 Profile views (`ProfileManagerView.swift`)

- **Current responsibility.** Profile create/edit/hide; `ProfileKind`/`ProfileManagementMode` UI lives here.
- **Current model/logic used.** No `targetValue`/`targetUnit`/`recordedValue` usage.
- **Expected V2 change.** Phase 7 adds Relationship create/view/revoke UI here. `ProfileKind`/`ManagementMode` UI is untouched (Phase Plan §7: not retired by this plan).
- **Which phase changes it.** Phase 7.
- **Tests affected.** None existing; new Phase 7 tests.
- **Risk level.** None from the target/recordedValue migration; low from Phase 7's additive UI.

### 4.10 Other seed/onboarding call sites: `LifeOSApp.swift`, `Models/SeedData.swift`, `RootTabView.swift`, `AddImprovementCategoryView.swift`

- **Current responsibility.** Sample/preview data (`LifeOSApp.swift`), first-run seed content (`SeedData.swift`), onboarding starter-plan Activity creation (`RootTabView.swift` line 294), "save Area as template" round-trip (`AddImprovementCategoryView.swift` line 271, copies `task.targetValue`/`targetUnit` when snapshotting a template).
- **Current model/logic used.** All construct or copy `Activity(targetValue:targetUnit:...)` directly.
- **Expected V2 change.** All four need updating in the same phase as `ImprovementTemplates.swift` (§3.6) — they're the same category of "static/seed Activity construction," and skipping any one of them means first-run onboarding silently keeps using the old field shape (which won't exist post-Phase-5) → build failure, not a silent bug, but still needs to be in scope, not discovered late.
- **Which phase changes it.** Phase 4.
- **Tests affected.** None directly unit-tested, but `RootTabView`'s onboarding flow is part of "Create activities/tasks" (must-keep-working feature #1) — manual verification required.
- **Risk level.** Medium — first-run experience, easy to overlook since none of these four files are "the obvious place" a developer would think to check first.

---

## 5. Tests

### 5.1 Existing tests affected (need updating, not just recompiling)

| Test file | What's affected | Why |
|---|---|---|
| `LifeOSUnitTests/TestFixtures.swift` | Confirmed **not** affected — its `targetValue` reference (line 51) is inside the `measure(...)` helper, constructing a `ResultMeasure`, not an `Activity`. No `Activity`/`ActivitySession` fixture helper currently exists in this file (call sites construct `Activity`/`ActivitySession` directly per-test). | Verified by grep + context read. |
| `LifeOSUnitTests/ProgressAndHierarchyTests.swift` | `testDailyProgressSumsOnlySelectedProfileAndDay` (lines ~16–50): constructs `Activity(targetValue:targetUnit:...)` and multiple `ActivitySession(recordedValue:...)`, asserts on `DailyActivityProgress.actual`/`.cappedFraction`. | Directly exercises the code changing in Phase 4. Needs rewriting to construct `MeasurementDefinition`/`MeasurementEntry` instead, with equivalent assertions. |
| `LifeOSUnitTests/PlanningServiceTests.swift` | Not in the grep hit list — **not affected.** Confirms `PlanningService`'s schedule engine (must-keep-working feature #2, #6) is structurally independent of the target/recordedValue model, exactly as expected. | Verified by grep — file absent from hit list. |
| `LifeOSUnitTests/TodayViewModelTests.swift` | Not in the grep hit list — **not affected.** `FakeCalendarRepository`/`TodayViewModel` tests don't touch `targetValue`/`recordedValue`. | Verified by grep — file absent from hit list. |
| `LifeOSUnitTests/PortableMetricServiceTests.swift` | `testEveryVersionOneEvidenceTypeMapsToPortableMetrics`, `testPortableJSONRoundTripPreservesTypedFlexibleFields`, `testFutureSchemaAndInvalidNumbersAreRejected` — construct `Activity`/`ActivitySession` with old fields, assert on exported JSON shape. | Directly exercises `PortableMetricService.swift` (§3.8), which changes in Phase 4. |
| `LifeOSComponentTests/GoalSystemComponentTests.swift` | Multiple tests construct `Activity(targetValue:targetUnit:...)` and `ActivitySession(recordedValue:...)` (lines 215, 235–236, 280, 295, 346, 352, 359, 404, 641, 652–653, 673). **Also contains unrelated `ResultMeasure.targetValue`/`baselineValue` usage (lines 508, 647, 663, 679) — leave those alone.** | This is an end-to-end component-test file; several of its scenarios (`testEndToEndBaseballDailyPracticeLifecycle`, `testEveryUserEditableTaskAndGoalFieldPersists`, `testScheduleEditReconcilesPersistedTodayDataForEveryScreen`) specifically exercise Activity+ActivitySession together and need the most careful rewriting of any test file in this migration, since they're asserting on cross-model behavior, not just field presence. |

### 5.2 New tests required

- `MeasurementDefinition`/`MeasurementEntry` basic construction (Phase 1).
- `MeasurementRepository`/`RelationshipRepository` CRUD against fakes, mirroring `FakeCalendarRepository` (Phase 2).
- Measurement-aggregation function tests: the worked 100+80+120→300 example from the proposal, plus edge cases — no entries, entries with only `nameSnapshot` match (no live `measurementDefinitionID`), entries outside the date range, multiple `MeasurementDefinition`s on one Activity (Phase 2).
- `DailyActivityProgress`/`dailyProgress` rewritten to assert against the new aggregation, replacing (not just editing) the current `testDailyProgressSumsOnlySelectedProfileAndDay` (Phase 4).
- `GoalProgressEngine` auto-rollup tests: linked vs. unlinked `ResultMeasure` behavior, the 300-ground-balls worked example applied to a Goal (Phase 6).
- `Relationship` permission-check tests, once a permission-check helper exists (Phase 7).
- A migration-completeness test: `grep -rn "targetValue\|targetUnit\|recordedValue"` returning zero hits outside historical docs, run as an explicit CI-style check before Phase 5's commit lands (not a Swift test, but should be a documented verification step).

---

## 6. Important Existing Behaviour — Responsible Files

| Must-keep-working feature | Primary files responsible | Affected by this migration? |
|---|---|---|
| 1. Create activities/tasks | `AddActivityView.swift`, `Models.swift` (`Activity`) | **Yes** — target field UI changes (Phases 3, 5); schedule/name/category fields untouched. |
| 2. Calendar scheduling | `PlanningService.swift`, `ScheduleRule` fields on `Activity` | **No** — confirmed zero overlap; schedule fields are entirely separate from target/recordedValue. |
| 3. Today view | `TodayTimelineView.swift`, `TodayViewModel.swift`, `CalendarRepository.swift` | **Minimally** — one caption function (`completionText`, lines 939–940); everything else (Plan cards via `ProgressMetric`, active/decided lists, actions) is confirmed independent. |
| 4. Week calendar view | `WeeklyScheduleView.swift` | **No** — confirmed zero references to the affected fields. |
| 5. Activity completion flow | `RecordActualView.swift`, `AddWhatHappenedView.swift` | **Yes, heavily** — these are the two most-affected View files in the entire migration. Highest-risk, highest-priority manual verification target. |
| 6. Existing scheduling logic and tests | `PlanningServiceTests.swift`, `PlanningService.swift` | **No** — confirmed zero overlap; this test file doesn't appear in the grep hit list at all. |

**Net read:** the migration is far more concentrated than "touches everything" — scheduling (#2, #6) and the Week view (#4) are structurally untouched, Today (#3) has one small isolated change, and the real risk concentrates in Activity creation/editing (#1) and the completion flow (#5), exactly where a user would notice a regression fastest.

---

## 7. Phase-by-Phase Change Map

| Phase | Models | Engine | Views | Tests |
|---|---|---|---|---|
| 1 | Add `Relationship`, `MeasurementDefinition`, `MeasurementEntry` to `Models.swift`/`SchemaVersioning.swift` | — | — | New model construction tests |
| 2 | — | New `MeasurementRepository.swift`, `RelationshipRepository.swift`; `ProgressEngine.swift` gains aggregation function | — | New repository + aggregation tests |
| 3 | — | — | `AddActivityView.swift`, `EditTaskView.swift` (Measurements section, additive); `RecordActualView.swift`, `AddWhatHappenedView.swift` (measurement recording, additive) | None new (UI-only, per Step 5 precedent) |
| 4 | — | `ProgressEngine.swift` (§3.1), `PortableMetricService.swift` (§3.8), `LifeOSBackupService.swift` (§3.7, new fields added, old still read for restore), `ImprovementTemplates.swift` (§3.6) | Every file in §4.1–4.6, §4.10 fully repointed at the new model | `ProgressAndHierarchyTests`, `PortableMetricServiceTests`, `GoalSystemComponentTests` rewritten; full suite green required |
| 5 | Remove `Activity.targetValue`/`targetUnit`, `ActivitySession.recordedValue`; `SchemaVersioning.swift` roster fingerprint updated | `LifeOSBackupService.swift` stops writing old fields | Remove old-field UI remnants in `AddActivityView.swift`/`EditTaskView.swift` | Migration-completeness grep check; full suite green |
| 6 | `ResultMeasure` gains optional `linkedMeasurementDefinitionID` | `CategoryProgressEngine.swift` (`GoalProgressEngine`) | `EditGoalViews.swift` | New `GoalProgressEngine` auto-rollup tests |
| 7 | — | New `RelationshipRepository.swift` consumed | `ProfileManagerView.swift` | New `Relationship` permission tests |

---

## 8. File Impact Table (all files, at a glance)

| File | Risk | Phase(s) |
|---|---|---|
| `Models/Models.swift` | Medium | 1, 5, 6 |
| `Models/SchemaVersioning.swift` | Low | 1, 5 |
| `Models/SeedData.swift` | Medium | 4 |
| `Engine/ProgressEngine.swift` | Medium | 2, 4 |
| `Engine/CategoryProgressEngine.swift` | None (this migration); Low (Phase 6) | 6 |
| `Engine/ProgressMetric.swift` | Low | (verify only, Phase 4) |
| `Engine/CalendarRepository.swift` | None | — |
| `Engine/TodayViewModel.swift` | None | — |
| `Engine/ImprovementTemplates.swift` | Medium | 4 |
| `Engine/LifeOSBackupService.swift` | Medium-high | 4, 5 |
| `Engine/PortableMetricService.swift` | Medium | 4 |
| `Engine/MeasurementRepository.swift` *(new)* | None | 2 |
| `Engine/RelationshipRepository.swift` *(new)* | None | 2, 7 |
| `Views/AddActivityView.swift` | Low (technical) / High (user-facing) | 3, 5 |
| `Views/EditTaskView.swift` | Medium | 3, 5 |
| `Views/RecordActualView.swift` | **High** | 3, 4 |
| `Views/AddWhatHappenedView.swift` | Medium-high | 4 |
| `Views/DailyProgressView.swift` | Medium-high | 4 |
| `Views/TodayTimelineView.swift` | Low | 4 |
| `Views/WeeklyScheduleView.swift` | None | — |
| `Views/ImprovementDashboardView.swift` | None (this migration) | — |
| `Views/EditGoalViews.swift` | None (this migration) / Low (Phase 6) | 6 |
| `Views/ProfileManagerView.swift` | None (this migration) / Low (Phase 7) | 7 |
| `Views/RootTabView.swift` | Medium | 4 |
| `Views/AddImprovementCategoryView.swift` | Medium | 4 |
| `LifeOSApp.swift` | Low | 4 |
| `LifeOSUnitTests/ProgressAndHierarchyTests.swift` | Medium | 4 |
| `LifeOSUnitTests/PortableMetricServiceTests.swift` | Medium | 4 |
| `LifeOSUnitTests/PlanningServiceTests.swift` | None | — |
| `LifeOSUnitTests/TodayViewModelTests.swift` | None | — |
| `LifeOSUnitTests/TestFixtures.swift` | None | — |
| `LifeOSComponentTests/GoalSystemComponentTests.swift` | **High** (largest, most cross-cutting rewrite) | 4 |

---

## 9. Risk Assessment

Consistent with `IMPLEMENTATION_PHASE_PLAN_V2.md` §0: the risk here is **behavioral regression, not data loss** (no production users/data exists). Ranking by that standard:

- **Highest risk:** `RecordActualView.swift` (completion flow, must-keep-working #5) and `GoalSystemComponentTests.swift` (largest cross-cutting rewrite, and the only test file exercising Activity+ActivitySession+Goal together end-to-end). A regression in either would be either immediately user-visible (the first) or would hide a real behavioral break behind a still-green build (the second, if not rewritten carefully).
- **Medium-high:** `AddWhatHappenedView.swift`, `DailyProgressView.swift`, `LifeOSBackupService.swift` (has its own real compatibility surface — a developer's own test backups — despite the "no users" context), `PortableMetricService.swift` (external contract).
- **Medium:** `Models.swift`, `ProgressEngine.swift`, `EditTaskView.swift`, `ImprovementTemplates.swift`, `RootTabView.swift`, `AddImprovementCategoryView.swift`, `SeedData.swift`, `ProgressAndHierarchyTests.swift`, `PortableMetricServiceTests.swift`.
- **Low or none:** everything confirmed to have zero overlap with the affected fields — `PlanningService.swift`/`PlanningServiceTests.swift` (scheduling), `WeeklyScheduleView.swift` (Week view), `TodayViewModel.swift`/`CalendarRepository.swift` (Today's core), `CategoryProgressEngine.swift`/`ImprovementDashboardView.swift`/`EditGoalViews.swift` (Goals — different `targetValue` field entirely), `ProfileManagerView.swift`, `TestFixtures.swift`.

The **single largest source of avoidable risk** is treating this as a mechanical find-and-replace across all files hit by the `targetValue`/`targetUnit`/`recordedValue` grep — as this document's own construction demonstrated, roughly a third of the raw grep hits (`CategoryProgressEngine.swift`, `ImprovementDashboardView.swift`, `EditGoalViews.swift`, most of `LifeOSBackupService.swift`/`PortableMetricService.swift`, `TestFixtures.swift`) belong to `ResultMeasure.targetValue`, a same-named but unrelated field. A search-and-replace approach would either miss real changes needed elsewhere in those files or corrupt unrelated `ResultMeasure` code. Every phase implementation should re-verify per-file scope against this document rather than re-running a blind grep.

---

## 10. Recommended Implementation Order

Matches `IMPLEMENTATION_PHASE_PLAN_V2.md`'s phase order exactly (1 → 7), with these sequencing notes specific to what this file-level analysis surfaced:

1. **Phase 1–2 as planned** — no new information changes these; low risk, foundational.
2. **Phase 3 as planned**, but explicitly budget `RecordActualView.swift` and `AddWhatHappenedView.swift` as the two hardest parts of this phase, not equal-effort siblings of `AddActivityView.swift`/`EditTaskView.swift` — the latter two are simpler form-field additions, the former two involve real UI/state redesign (dynamic Stepper-per-measurement instead of one fixed Stepper).
3. **Before Phase 4 starts:** re-run the `targetValue`/`targetUnit`/`recordedValue` grep fresh (this document is a snapshot; files may have changed since) and diff against §8's table — confirm no new call site appeared and no listed one disappeared.
4. **Phase 4, suggested internal ordering** (not a phase split — still one commit per Phase Plan's atomicity rule, but an ordering for the *work*, so partial progress is coherent if interrupted): Models/Engine first (`ProgressEngine.swift`, aggregation), then the four seed/template files (§4.10) together since they're mechanically similar, then the two high-risk completion-flow views, then `DailyProgressView.swift`, then the two contract-surface files (`LifeOSBackupService.swift`, `PortableMetricService.swift`) last, since they depend on the model shape being finalized by everything before them.
5. **Phase 5** exactly as planned — should be mechanical if Phase 4 was thorough.
6. **Phase 6–7** independent of 1–5's completion in principle, but sequenced after per the existing plan; no new information changes this.

---

## 11. Unknowns / Questions Before Coding

Carried forward from `DOMAIN_MODEL_V2_PROPOSAL.md` §6 (still open, now with file-level stakes attached) plus new ones surfaced by this file-level pass:

1. **(Proposal Q1, now higher-stakes)** Does every `Activity` get a `MeasurementDefinition` even for a simple single target, or is there still a "no measurements configured, just completion tracking" state? This determines whether `AddActivityView`/`EditTaskView`'s Phase 3 UI is "always show the Measurements section" or "show it only when the user opts in," which is a real, different UI to build.
2. **(New)** `ImprovementTemplates.swift`'s blueprint format (§3.6) — does the template-definition data structure itself need a shape change (e.g., `measurements: [(name, type, unit, target)]`), or does template-apply-time construct one `MeasurementDefinition` per legacy `targetValue`/`targetUnit` pair automatically? This is a concrete data-format decision, not just "update the call site."
3. **(New)** `LifeOSBackupService.swift`'s backup schema version — does the backup-format version bump happen in lockstep with Phase 4/5, or does backup/restore need to keep reading old-format backups for some period (i.e., does *this* surface need Option A's coexistence discipline even though the SwiftData store itself doesn't)? This is a real product question: can a user (developer, currently) restore an old backup after upgrading past Phase 5?
4. **(New)** `PortableMetricService.swift`'s exported JSON shape for multi-measurement sessions — array of `{name, type, value, unit}` under the existing `action_session` event kind, or a new event kind entirely? Affects any external consumer of this contract (none exist yet per DESIGN.md, but the contract is explicitly designed for future Android/analytics use).
5. **(New)** `GoalSystemComponentTests.swift`'s end-to-end scenarios — should Phase 4 rewrite these to cover the new multi-measurement model's cross-cutting behavior more thoroughly than the old single-value model did (e.g., a test with 3 simultaneous `MeasurementDefinition`s on one Activity, matching the Baseball Fielding example), or should Phase 4 stay strictly behavior-preserving (same scenarios, updated field access) and treat richer multi-measurement component tests as separate, later work?
6. Proposal §6's Open Questions 4, 5, 6, 7 remain open and are not newly informed by this file-level pass — still need product decisions before Phase 6 (Q3/Q4) and Phase 7 (Q5) specifically.

**Stopping here per instruction. No implementation started.**
