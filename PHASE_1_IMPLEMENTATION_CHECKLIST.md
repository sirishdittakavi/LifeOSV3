# LifeOS — Phase 1 Implementation Checklist

**Status:** Documentation only. No code modified, nothing implemented.
**Source of truth:** `IMPLEMENTATION_PHASE_PLAN_V2.md`, `CODE_CHANGE_MAP.md`, `DOMAIN_MODEL_V2_PROPOSAL.md`.
**Scope:** Phase 1 only. Phase 1 is preparation — it adds three new, completely inert model types and nothing else. Nothing reads or writes them yet; no existing file's behavior changes.

---

## 1. Phase 1 Goal

Add three new SwiftData model types — `Relationship`, `MeasurementDefinition`, `MeasurementEntry` — to the schema, purely additively, with **zero** behavior change to anything that exists today.

Explicitly, Phase 1 does **not**:
- Wire the new models into any Repository, Engine, or View (that's Phases 2–3).
- Touch `Activity.targetValue`/`targetUnit` or `ActivitySession.recordedValue` in any way — not read, not written, not deprecated, not annotated. Those fields, and the `Activity`/`ActivitySession` class bodies as a whole, are not part of this phase's diff at all.
- Change any UI flow. Activity creation, activity completion, calendar scheduling, and Today/Week views are unaffected because nothing in this phase is reachable from them yet.
- Create a versioned SwiftData migration. Per `IMPLEMENTATION_PHASE_PLAN_V2.md` §0 (Option B, pre-release context), the three new types are added directly to the existing `LifeOSSchemaV1` roster — there is no `LifeOSSchemaV2`, no `MigrationStage`, no migration to write or test in this phase.

**Done-state in one sentence:** three new, empty, unused tables exist in the schema; every existing test still passes unchanged; the app still builds and behaves identically in every observable way.

---

## 2. Files to Create

| New file | Purpose |
|---|---|
| `LifeOSUnitTests/MeasurementAndRelationshipModelTests.swift` | Basic construction tests for the three new model types — default field values, required-vs-optional fields, that a constructed instance's properties round-trip as expected. Not integration tests (nothing to integrate with yet) — just confirms the models are shaped correctly in isolation. |

No new production (`LifeOS/`) files. `Relationship`, `MeasurementDefinition`, and `MeasurementEntry` are added as new classes inside the existing `Models.swift`, not new files — consistent with how every other model in this codebase lives in that one file already.

---

## 3. Files Allowed to Change

Exactly these, and nothing else:

1. **`LifeOS/Models/Models.swift`** — add three new `@Model final class` declarations (`Relationship`, `MeasurementDefinition`, `MeasurementEntry`). No existing class in this file is edited, reordered, or reformatted.
2. **`LifeOS/Models/SchemaVersioning.swift`** — add the three new types to `LifeOSSchemaV1.models`, and update `LifeOSSchemaV1.releaseFingerprint` to include their names. The comment block documenting the "preserve V1 immutably before an incompatible change" process may be read but should not be edited to contradict itself — see §5 for why this addition doesn't violate that documented rule.
3. **`LifeOSUnitTests/MeasurementAndRelationshipModelTests.swift`** *(new — see §2)*.
4. **`LifeOS.xcodeproj/project.pbxproj`** — *only if* Xcode-target parity is wanted for the new test file. The project uses explicit file references (not synchronized folder groups, confirmed earlier this session), so `swift test` (SPM) picks up a new file under `LifeOSUnitTests/` automatically with no project-file edit, but the Xcode-based `LifeOSUnitTests` target inside `LifeOS.xcodeproj` will not compile the new file until it's registered (`PBXBuildFile`, `PBXFileReference`, group membership, `Sources` build phase — the same four-point registration this session used for `CalendarRepository.swift`/`TodayViewModel.swift`/`ProgressMetric.swift`). Not required for the verification steps in §7, which rely on `swift test`.
5. **`Refactor.md`** — log Phase 1's completion, per this session's established pattern of updating it after every completed step. Documentation, not implementation.

**Not changed:** `Package.swift`. `LifeOSUnitTests`' SPM test target has no explicit `sources:` list (it globs the whole `LifeOSUnitTests/` folder), so the new test file is picked up automatically. `Models/Models.swift` and `Models/SchemaVersioning.swift` are already in the `LifeOS` target's `sources:` list — adding classes inside an already-listed file needs no `Package.swift` edit.

---

## 4. Files That Must NOT Change

**Explicitly protected, per instruction:**

- `LifeOS/Engine/PlanningService.swift`
- `LifeOSUnitTests/PlanningServiceTests.swift`
- `LifeOS/Views/WeeklyScheduleView.swift`
- `LifeOS/Engine/TodayViewModel.swift`
- `LifeOS/Engine/CalendarRepository.swift`

**Also protected — behaviorally, and therefore every file responsible for the behavior:**

- **Existing scheduling behaviour** → `PlanningService.swift` (above), and by extension every file that calls it without modification: `TodayTimelineView.swift`, `WeeklyScheduleView.swift` (above), `EditTaskView.swift`'s schedule fields, `AddActivityView.swift`'s schedule fields.
- **Calendar behaviour** → `CalendarRepository.swift` (above), `TodayViewModel.swift` (above), `PlanningService.swift`'s `CalendarItem` generation.
- **Activity creation flow** → `LifeOS/Views/AddActivityView.swift` — must not change in this phase. (Phase 3 is where its target-field UI eventually grows a Measurements section; that is explicitly not this phase.)
- **Activity completion flow** → `LifeOS/Views/RecordActualView.swift`, `LifeOS/Views/AddWhatHappenedView.swift` — must not change in this phase. Per `CODE_CHANGE_MAP.md` §4.3/§4.4, these are the highest-risk files in the *eventual* migration; Phase 1 touching them at all would be scope creep this checklist exists to prevent.

**Everything else not listed in §3 is implicitly protected by the same rule: if it's not one of the five files in §3, it does not change in Phase 1.** This explicitly includes, without limitation: `ProgressEngine.swift`, `CategoryProgressEngine.swift`, `ProgressMetric.swift`, `DailyProgressView.swift`, `TodayTimelineView.swift`, `EditTaskView.swift`, `ImprovementDashboardView.swift`, `EditGoalViews.swift`, `ProfileManagerView.swift`, `LifeOSBackupService.swift`, `PortableMetricService.swift`, `ImprovementTemplates.swift`, `SeedData.swift`, `RootTabView.swift`, `AddImprovementCategoryView.swift`, `LifeOSApp.swift`, every Nutrition/Weight/Sport view, and every existing test file other than the one new file in §2.

**Fields that must not change, explicitly:**
- `Activity.targetValue` — untouched.
- `Activity.targetUnit` — untouched.
- `ActivitySession.recordedValue` — untouched.
- No new field, relationship, or computed property is added to `Activity` or `ActivitySession` in this phase either — the new models reference them one-directionally (see §5), the same pattern `CalendarItem.activity: Activity?` already uses today without `Activity` needing an inverse collection. **`Activity.swift` and `ActivitySession.swift` class bodies are not part of this phase's diff at all.**

---

## 5. Schema Changes

*(Documented for review — not implemented in this phase, per instruction.)*

### New entities

**`Relationship`** — generic Person ↔ Person connection. Per `DOMAIN_MODEL_V2_PROPOSAL.md` §2.2:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `subjectProfileID` | `UUID` | The profile being acted upon/observed |
| `actorProfileID` | `UUID` | The profile with the grant |
| `relationshipType` | `String` | User-facing label, not a closed enum |
| `permissionsRaw` | `[String]` or similar storable set encoding | `view`/`edit`/`manageActivities`/`receiveNotifications`/`viewProgress` |
| `statusRaw` | `String` (backing a `status` enum: `pending`/`active`/`revoked`) | |
| `createdAt` | `Date` | |
| `respondedAt` | `Date?` | |

Relationships to existing models: references two `Profile`s **by UUID**, not by SwiftData relationship pointer, in this phase — Phase 1 does not add an inverse `relationships: [Relationship]` collection to `Profile`, matching the "don't touch existing classes" constraint in §4. (Whether to later convert to a live SwiftData relationship is a Phase 7 UI-time decision, not a Phase 1 one.)

**`MeasurementDefinition`** — reusable "thing to track" attached to an Activity. Per proposal §2.7:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `activity` | `Activity?` | One-directional reference, same pattern as `CalendarItem.activity` |
| `name` | `String` | |
| `typeRaw` | `String` (backing a `type` enum: `count`/`duration`/`distance`/`percentage`/`rating`/`text`/`custom`) | |
| `unit` | `String?` | |
| `targetValue` | `Double?` | |
| `isOptional` | `Bool` | |
| `sortOrder` | `Int` | |
| `isActive` | `Bool` | |

**`MeasurementEntry`** — actual recorded value for one measurement within one session. Per proposal §2.8:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `activitySession` | `ActivitySession?` | One-directional reference |
| `measurementDefinition` | `MeasurementDefinition?` | **Optional soft link** — deliberately not required, so a `MeasurementDefinition` can be edited/archived/deleted later without corrupting historical entries (see proposal §2.8's full rationale) |
| `nameSnapshot` | `String` | Copied from the definition at creation time |
| `typeSnapshot` | same enum as `MeasurementDefinition.type` | Copied at creation time |
| `unitSnapshot` | `String` | Copied at creation time |
| `numericValue` | `Double?` | |
| `textValue` | `String?` | |
| `recordedAt` | `Date` | |

### Relationships (this phase)

- `MeasurementDefinition → Activity`: many-to-one, one-directional (new model points at existing model; `Activity` gains no new field).
- `MeasurementEntry → ActivitySession`: many-to-one, one-directional (same pattern).
- `MeasurementEntry → MeasurementDefinition`: many-to-one, **optional**, one-directional.
- `Relationship → Profile` (×2, subject and actor): by UUID reference in this phase, not a live SwiftData relationship (see above).

### Migration version

**No version bump.** Per `IMPLEMENTATION_PHASE_PLAN_V2.md` §0: LifeOS is pre-release with no production users, so `LifeOSSchemaV1`'s documented "never change this roster after release" rule does not apply — V1 was never released. The three new types are added directly to `LifeOSSchemaV1.models`. There is no `LifeOSSchemaV2`, no `MigrationStage`, and this phase does not implement one. Existing local/simulator SwiftData stores created before this change will fail to open against the new roster (SwiftData has no path to auto-resolve an unrecognized shape without a migration plan) — this is expected; the fix is deleting and reinstalling the app on the simulator, not a migration. **No migration is implemented in this phase, and none is required.**

---

## 6. Tests Required

**New tests** (in the new file from §2):
- `Relationship` constructs with expected default/required field behavior.
- `MeasurementDefinition` constructs with expected default/required field behavior, including each `type` case.
- `MeasurementEntry` constructs with expected default/required field behavior, including the optional `measurementDefinition` link being genuinely optional (construct one with it `nil` and confirm the entry is still fully valid/usable).

**Existing tests that must remain passing, unchanged, at the same count:**
- `LifeOSUnitTests/PlanningServiceTests.swift` — full file (25 tests as of this session).
- `LifeOSUnitTests/ProgressAndHierarchyTests.swift` — full file.
- `LifeOSUnitTests/TodayViewModelTests.swift` — full file.
- `LifeOSUnitTests/GoalProgressEngineTests.swift` — full file.
- `LifeOSUnitTests/PortableMetricServiceTests.swift` — full file.
- `LifeOSComponentTests/GoalSystemComponentTests.swift` — full file.
- **All 80 tests from the current suite** (this session's last confirmed count) — the acceptance bar is the *same* 80 passing, not "the suite still mostly passes."

**Regression tests required.** None beyond the above. Phase 1 changes no existing behavior, so there is nothing new to regression-test — the existing suite passing unchanged *is* the regression test. If any existing test needs to change to keep passing, that is a signal Phase 1 has exceeded its scope (see §4) and should be corrected, not accepted.

---

## 7. Verification Steps

Run in this order:

1. **`swift build`** — confirms the SPM package (`LifeOSCore`) compiles with the new models added.
2. **`swift test`** — full headless suite. Expected result: **80 existing tests pass + the new construction tests pass**, zero failures, zero skipped.
3. **`xcodebuild build -project LifeOS.xcodeproj -scheme LifeOS -destination "platform=iOS Simulator,id=<simulator-id>"`** — confirms the full app target (Views included) still compiles against the widened model roster. Expected result: **BUILD SUCCEEDED**.
4. **Do not run `xcodebuild test`** for this phase's verification — the `LifeOSUITests` target has a pre-existing, unrelated compile error (noted earlier this session) that blocks it regardless of this change; it is not part of Phase 1's acceptance bar.
5. **Diff review**: `git diff --stat` against the phase's changes should show exactly the files listed in §3, nothing else. If any file outside that list appears, stop and investigate before committing.
6. **(Expected, not a failure)** If a local/simulator SwiftData store already exists from before this change, the app will fail to launch against it — delete the app from the simulator and reinstall, per §5.

**Expected results summary:** clean build (SPM and Xcode), 80+N tests green, diff scoped to exactly the five files in §3, no UI or behavior change observable anywhere in the app.

---

## 8. Rollback Plan

1. `git revert` the single Phase 1 commit. Because Phase 1 is purely additive and touches no existing class, function, or UI, the revert is clean by construction — there is nothing for a reverted state to be "half-way" between.
2. If a local/simulator SwiftData store was created *after* this phase's change (i.e., under the widened roster), it will fail to open once reverted, for the same reason described in §5 — delete the app from the simulator and reinstall. This is the same disposable-dev-store posture `IMPLEMENTATION_PHASE_PLAN_V2.md` §0 already establishes for the whole V2 effort, not something new to this phase.
3. No data-loss concern in either direction — there is no production data, and everything this phase adds is unused by any other code, so reverting it cannot leave any other feature in a broken or partially-migrated state.

---

## 9. Acceptance Criteria

Phase 1 is complete when **all** of the following hold:

- [ ] `Relationship`, `MeasurementDefinition`, `MeasurementEntry` exist in `Models.swift` with the fields documented in §5.
- [ ] `LifeOSSchemaV1.models` includes all three new types; `releaseFingerprint` is updated to match.
- [ ] `Activity.swift`/`ActivitySession.swift` class bodies are byte-for-byte unchanged (verify via `git diff` showing zero hunks touching those class declarations).
- [ ] No file outside §3's list appears in the phase's diff.
- [ ] `swift build` succeeds.
- [ ] `swift test` reports the full existing suite passing at its prior count, plus the new construction tests passing — zero failures.
- [ ] `xcodebuild build` (full app target) succeeds.
- [ ] No View, Repository, or Engine function anywhere in the codebase references `Relationship`, `MeasurementDefinition`, or `MeasurementEntry` yet — grep confirms zero call sites outside `Models.swift`, `SchemaVersioning.swift`, and the new test file.
- [ ] `Refactor.md` is updated logging Phase 1's completion, commit hash, and test results, per this session's established documentation pattern.
- [ ] **Phase 2 has not been started.** No `MeasurementRepository.swift`/`RelationshipRepository.swift` exist yet; no aggregation function has been added to `ProgressEngine.swift`.

**Stopping here per instruction. No implementation started.**
