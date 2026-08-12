# LifeOS — Implementation Phase Plan V2

**Status:** Planning document only. No code in this document; describes what future phases will touch.
**Converts:** `DOMAIN_MODEL_V2_PROPOSAL.md` into an ordered sequence of safe, independently-committable, independently-rollback-able phases.
**Revision (2026-08-12):** Updated per explicit direction — LifeOS is pre-release with no production users or existing user data. The original plan (below, superseded) optimized for backward-compatible data migration as the primary risk. That's no longer the right priority. See §0.

---

## 0. Migration Strategy Decision

### Context that changes everything

LifeOS has no production users and no existing user data to protect. The original version of this plan (git history) inherited its caution from Refactor.md Step 6's Nutrition stop — which was the *correct* call there, because Step 6 was evaluated as if real user data already existed. That assumption no longer holds for this plan. Re-deriving the decision from scratch:

**Priority order, as given:**
1. Build the correct long-term V2 architecture.
2. Preserve current *working behaviour*.
3. Avoid unnecessary V1 technical debt.

**The operative principle: preserve behaviour, not necessarily the old data model.**

`Activity.targetValue`, `Activity.targetUnit`, and `ActivitySession.recordedValue` are the old single-metric model. Nothing requires them to survive as fields — what must survive is what they *do*: a user can set a target on an Activity, record a value against it, and see progress. `MeasurementDefinition`/`MeasurementEntry` can be that mechanism directly, from the start, rather than a second system bolted on next to the first.

### Option A — Additive migration (keep old fields temporarily)

Keep `targetValue`/`targetUnit`/`recordedValue` indefinitely, add `MeasurementDefinition`/`MeasurementEntry` alongside, defer removal to an unscheduled later phase. This was the original plan.

- **Pro:** Maximally safe against data loss.
- **Con, given the actual context here:** solves a problem that doesn't exist (there's no real data to lose) while creating a real one — two parallel ways to record "how much did I do" (`Activity.targetValue` vs. `MeasurementDefinition`, `ActivitySession.recordedValue` vs. `MeasurementEntry`), which every future read site (`ProgressEngine.dailyProgress`, `DailyActivityProgress`, `RecordActualView`, `AddActivityView`'s target field, `DailyProgressView`) has to know to check both of. That's exactly the "unnecessary V1 technical debt" the priority list says to avoid, and it's debt with no offsetting safety benefit here.

### Option B — Clean V2 replacement (remove old fields after tests)

Replace `targetValue`/`targetUnit`/`recordedValue` with `MeasurementDefinition`/`MeasurementEntry` directly. Every existing call site is updated in the same phase, not left on a legacy path. No dual-write period.

- **Pro:** No parallel systems, no debt, matches "build the correct long-term architecture" directly instead of via a detour.
- **Con:** Larger single phase (every read/write site of the old fields must move together, or the app doesn't build/work) — but "larger" here means *more files in one phase*, not *migration of real data*, since there is none.

### Recommendation: **Option B**, with the risk-reduction moved from "data migration safety" to "behavioral regression safety"

Given no real data exists, Option A's entire risk-reduction premise (protect data already on real devices) doesn't apply — there's nothing on a real device to protect. Its cost (permanent dual-model complexity) is real regardless. Option B is the safer choice **for this context specifically**, not safer in the abstract — the same reasoning that stopped Step 6 (real data, formal migration required) argues *for* Option B here (no real data, formal migration is unnecessary ceremony).

This does **not** mean "move fast and skip testing." It means: replace the *data-loss safety net* (V1-store fixture, versioned `MigrationStage`, staged rollout) with a *behavioral safety net* — the existing 80-test suite plus the six must-keep-working features below, gating every phase. The risk that matters now is regressing Today, Week, scheduling, or activity completion, not losing a production user's history.

### Consequence for `SchemaVersioning.swift`

Its documented process ("preserve released V1 model definitions as immutable historical types... before an incompatible @Model change ships") is written for a *released* schema. `LifeOSSchemaV1` here was never released to real users, so it does not need to be preserved immutably. The phases below **edit `LifeOSSchemaV1`'s model roster directly** rather than defining `LifeOSSchemaV2`/`V3` with formal migration stages. Once LifeOS actually ships to real users, this document's governing principle flips back to Option A's caution for all *future* changes — this decision is specific to the current pre-release state, not a permanent policy change to how the app handles schema evolution after release.

### Rollback approach (replaces the per-phase "corrective forward-fix" plan from the superseded version)

Because there is no real data:
- **Rollback of a phase = `git revert` the phase's commit(s).** No compensating migration is ever needed, because there is no live schema state on a real device to reconcile.
- **Local/simulator dev stores are disposable.** If a schema change makes an existing local SwiftData store unreadable (SwiftData throws on an unrecognized shape with no migration path), the fix is deleting the app from the simulator/device and reinstalling — `SeedData.swift` repopulates a usable starting state. This is explicitly an acceptable cost pre-release and is *why* Option B is affordable now in a way it won't be later.
- **The one thing that still needs a real safety net is behavior, not data** — hence gating every phase on the full test suite plus a manual pass over the six must-keep-working features, not on a migration fixture.

### Which existing features must remain unchanged (behaviorally, not necessarily by field)

These are the acceptance bar for every phase below:

1. **Create activities/tasks** — `AddActivityView` flow, including setting a target (now via `MeasurementDefinition` instead of `targetValue`/`targetUnit`, but the user-facing capability — name it, set a number and unit, save — must work identically).
2. **Calendar scheduling** — `PlanningService`'s schedule engine (once/daily/selected-weekdays/timesPerDay/timesPerWeek), untouched by this plan; no phase below touches `ScheduleRule`'s embedded fields.
3. **Today view** — `TodayTimelineView`/`TodayViewModel`, including the Plan cards' progress bars (already routed through `ProgressMetric` per Refactor.md Step 7 — the aggregation source changes, the card behavior doesn't).
4. **Week calendar view** — `WeeklyScheduleView`, untouched by this plan.
5. **Activity completion flow** — `RecordActualView`/`AddWhatHappenedView`, including recording a value against a target (now via `MeasurementEntry` instead of `recordedValue`, same user-facing action).
6. **Existing scheduling logic and tests** — every `PlanningServiceTests`/`ProgressAndHierarchyTests` test not specifically about `targetValue`/`recordedValue` must keep passing unmodified; tests that *do* reference those fields get updated in the same phase that removes the fields, not left broken.

### Risks (of Option B specifically, given this context)

- **Engineering risk, not data risk.** The real risk in Option B is a phase that removes a field before every read site is updated, breaking the build or silently breaking a behavior (e.g., `DailyProgressView`'s progress bars going blank because `DailyActivityProgress` still reads `activity.targetValue`). Mitigation: the field-removal phase (Phase 5 below) is scoped to include *every* call site in the same commit, verified by a full build (not just the touched files) before that commit lands.
- **Test churn.** Several existing tests construct `Activity`/`ActivitySession` with `targetValue`/`recordedValue` directly (`TestFixtures`, `PlanningServiceTests`, `ProgressAndHierarchyTests`, `TodayViewModelTests`). These need updating alongside the model change, not after — a phase that changes the model but leaves tests red is not complete.
- **Scope creep risk.** "We can replace internal models freely" is true, but doesn't mean doing so everywhere at once. This plan still phases the work (below) so each commit is reviewable and revertible on its own, even though the safety net per phase is now "tests + build," not "migration fixture."
- **Premature commitment to Option B if requirements are still moving.** If the measurement model's shape (Open Questions 1, 4, 7 from the proposal) is still likely to change before any real usage, replacing the old fields now risks doing the replacement twice. Recommend confirming those open questions are settled (or settled enough) before Phase 4 specifically, since that's the point of no easy return.

---

## Phase 1 — Additive schema: Relationship, MeasurementDefinition, MeasurementEntry

**Purpose.** Introduce the three new entities from the proposal directly into the existing schema. No versioning ceremony — `LifeOSSchemaV1`'s model roster gains three types.

**What files change.**
- `LifeOS/Models/Models.swift` — add `final class Relationship`, `final class MeasurementDefinition`, `final class MeasurementEntry` (fields per `DOMAIN_MODEL_V2_PROPOSAL.md` §2.2, §2.7, §2.8).
- `LifeOS/Models/SchemaVersioning.swift` — add the three types to `LifeOSSchemaV1.models` and to `releaseFingerprint`. No new `VersionedSchema` enum, no `MigrationStage` — this is still schema V1, just with a larger roster, since V1 was never released.
- `Package.swift` — no change (Models.swift already included).

**What tests.** New unit tests for `Relationship`/`MeasurementDefinition`/`MeasurementEntry` basic construction. Full existing suite (80 tests) must still pass unchanged, since no existing model is touched yet.

**Migration risk.** None. Local/simulator SwiftData stores created before this phase will fail to open against the new roster (no migration path defined, by design) — delete and reinstall the app on the simulator, per §0's rollback approach. This is expected and acceptable pre-release.

**Commit boundary.** One commit: `feat: add Relationship, MeasurementDefinition, MeasurementEntry`.

**Rollback plan.** `git revert` the commit. Delete/reinstall the local dev app if its store was created under the new roster.

---

## Phase 2 — Repository and Engine layer for the new entities

**Purpose.** Same as the superseded plan: Repository + Engine layer for the new entities, following the `CalendarRepository`/`TodayViewModel` pattern (Refactor.md Step 4). Pure Engine code, no UI.

**What files change.**
- New: `LifeOS/Engine/MeasurementRepository.swift` — protocol + SwiftData implementation.
- New: `LifeOS/Engine/RelationshipRepository.swift` — same pattern.
- `LifeOS/Engine/ProgressEngine.swift` — add the measurement-aggregation function (sum matching `MeasurementEntry.numericValue` for an ActivityTemplate/date-range).
- `Package.swift` — add the two new Engine files to the testable target.

**What tests.** Focused unit tests: repository CRUD against a fake (style of `FakeCalendarRepository`); aggregation function tests covering the worked example from the proposal (100+80+120 → 300, 100% of a 300 target) plus edge cases.

**Migration risk.** None — no schema change, new code operating on Phase 1's tables.

**Commit boundary.** One commit: `feat: add MeasurementRepository, RelationshipRepository, and measurement aggregation`.

**Rollback plan.** `git revert`. No schema or existing-screen impact.

---

## Phase 3 — UI: manage MeasurementDefinitions and record MeasurementEntries (additive, old fields still present)

**Purpose.** Add the user-facing capability to create `MeasurementDefinition`s and record `MeasurementEntry` values, **while `targetValue`/`targetUnit`/`recordedValue` still exist and still work** — this phase is intentionally still additive, because introducing new UI and removing old fields in the same phase would conflate two different kinds of risk (UX risk vs. build-breakage risk). Field removal is isolated to Phase 5.

**What files change.**
- `LifeOS/Views/EditTaskView.swift` / `LifeOS/Views/AddActivityView.swift` — add a "Measurements" section for creating/editing `MeasurementDefinition`s, alongside the existing target field.
- `LifeOS/Views/RecordActualView.swift` / `LifeOS/Views/AddWhatHappenedView.swift` — when an Activity has `MeasurementDefinition`s, show fields to record `MeasurementEntry` values, in addition to the existing recorded-value field.

**What tests.** No new Engine tests needed (Phase 2 covers the logic). Verify via one full app build plus a manual pass over the six must-keep-working features from §0, focused on "create activities/tasks" and "activity completion flow" specifically, since those are the two this phase touches.

**Migration risk.** None — additive UI, existing fields/flows unmodified.

**Commit boundary.** One commit: `feat: add MeasurementDefinition/MeasurementEntry UI (additive)`.

**Rollback plan.** `git revert`. Existing target/recordedValue flow was never touched, so rollback is clean.

---

## Phase 4 — Migrate every read/write site from the old fields to the new model

**Purpose.** The actual "replace, don't coexist" step. Every place in the codebase that reads or writes `Activity.targetValue`/`targetUnit` or `ActivitySession.recordedValue` is updated to read/write `MeasurementDefinition`/`MeasurementEntry` instead. After this phase, the old fields are unused (dead code) but still present in the model — deletion is deferred one more phase (Phase 5) so this phase can be verified in isolation before anything is removed.

**Known call sites to update (from this session's context; re-verify exhaustively at implementation time via `grep -rn "targetValue\|targetUnit\|recordedValue"`):**
- `LifeOS/Engine/ProgressEngine.swift` — `DailyActivityProgress.target`, `dailyProgress(...)`.
- `LifeOS/Engine/CategoryProgressEngine.swift` — anywhere `activity.targetValue`/`targetUnit` feeds `CategoryProgress`.
- `LifeOS/Views/AddActivityView.swift`, `EditTaskView.swift` — the single target field's read/write.
- `LifeOS/Views/RecordActualView.swift`, `AddWhatHappenedView.swift` — `recordedValue` read/write, `ActivitySession(...)` construction.
- `LifeOS/Views/DailyProgressView.swift` — `ProgressBarRow`, `TrendRow` (both consume `DailyActivityProgress`/`ActivitySession.recordedValue` directly).
- `LifeOS/Views/TodayTimelineView.swift` — `overviewSnapshot`'s task-completion path if it touches target fields anywhere beyond what Step 7 already moved to `ProgressMetric`.
- `LifeOS/Engine/LifeOSBackupService.swift` — backup/restore encoding of `Activity`/`ActivitySession`.
- `LifeOS/Engine/PortableMetricService.swift` — if it encodes `targetValue`/`recordedValue` into the portable JSON contract.
- Tests: `LifeOSUnitTests/TestFixtures.swift`, `PlanningServiceTests.swift`, `ProgressAndHierarchyTests.swift`, `TodayViewModelTests.swift` — every fixture/assertion referencing the old fields.

**What tests.** This phase is not complete until the **full existing suite passes**, not a focused subset — because the whole point is confirming nothing that depended on the old fields silently broke. Any test that specifically asserted old-field behavior gets rewritten to assert the equivalent `MeasurementDefinition`/`MeasurementEntry` behavior, not deleted.

**Migration risk.** **Medium — engineering/regression risk, not data risk.** This is the largest single phase by file count. Mitigation: land it as one commit only when the full suite is green and a manual pass confirms all six must-keep-working features from §0, especially Today's Plan cards (which read `DailyActivityProgress`) and the completion flow.

**Commit boundary.** One commit: `refactor: migrate Activity/ActivitySession reads to MeasurementDefinition/MeasurementEntry`. Deliberately one commit, not split — a half-migrated state (some call sites on old fields, some on new) is worse than either extreme and shouldn't be allowed to exist even transiently in history.

**Rollback plan.** `git revert` the single commit — since it's atomic, revert returns every call site to the old fields simultaneously, which still exist (removal is Phase 5). No data implications since there's no real data.

---

## Phase 5 — Remove the old fields

**Purpose.** Delete `Activity.targetValue`, `Activity.targetUnit`, `ActivitySession.recordedValue` from the models, now that Phase 4 confirmed nothing reads them.

**What files change.**
- `LifeOS/Models/Models.swift` — remove the three fields from `Activity`/`ActivitySession`.
- `LifeOS/Models/SchemaVersioning.swift` — update `releaseFingerprint` to reflect the new roster shape (still V1, per §0 — no released version to preserve).
- Grep for any remaining reference (`grep -rn "targetValue\|targetUnit\|recordedValue"`) — should return nothing outside historical comments/docs; if it returns a hit, Phase 4 wasn't actually complete and this phase should not proceed until it is.

**What tests.** Full suite must pass with zero references to the removed fields anywhere in test code. This is confirmation, not new test-writing — Phase 4 already did the real work.

**Migration risk.** Low, *if and only if* Phase 4 is verified complete first. This phase should feel anticlimactic (deleting confirmed-dead fields) — if it doesn't, that's a signal Phase 4 wasn't actually done.

**Commit boundary.** One commit: `refactor: remove Activity.targetValue/targetUnit and ActivitySession.recordedValue`.

**Rollback plan.** `git revert`. Local/simulator stores created under the reduced roster won't reopen under the reverted (wider) roster — delete/reinstall, per §0.

---

## Phase 6 — Goal auto-rollup from MeasurementEntry

**Purpose.** Unchanged in substance from the superseded plan: let a `ResultMeasure` optionally derive progress from summed `MeasurementEntry` values. Still depends on Open Question 3 (proposal doc) being resolved before the UX is built — the schema/engine piece is low-risk regardless.

**What files change.**
- `LifeOS/Models/Models.swift` — add optional `linkedMeasurementDefinitionID: UUID?` to `ResultMeasure`. Per §0, added directly to the existing roster, no versioned migration stage.
- `LifeOS/Engine/CategoryProgressEngine.swift` (`GoalProgressEngine`) — use the Phase 2 aggregation function when the link is set, fall back to manual `ResultEntry` otherwise.
- `LifeOS/Views/EditGoalViews.swift` — UI to link a `ResultMeasure` to a `MeasurementDefinition`.

**What tests.** Focused `GoalProgressEngine` tests: auto-derived progress matches the manual-entry path's output shape; manual entry still works unchanged for unlinked measures; the worked 300-ground-balls example from the proposal.

**Migration risk.** None — additive optional field, existing Goals unaffected.

**Commit boundary.** One commit: `feat: add optional Goal auto-rollup from MeasurementEntry`.

**Rollback plan.** `git revert`. Existing manual-`ResultEntry` Goals structurally unaffected either way.

---

## Phase 7 — Relationship UI

**Purpose.** Unchanged from the superseded plan: UI to create/view/revoke `Relationship` records, gated by Open Question 5's resolution. `ProfileKind`/`ProfileManagementMode` are not removed in this phase — no urgency to retire them given no real users depend on the distinction either way; retiring them is a product-scope decision, not a technical-debt one, so it's left out of this plan entirely rather than deferred-and-tracked.

**What files change.** `LifeOS/Views/ProfileManagerView.swift` — Relationship create/view/revoke UI. No changes to `Profile.kind`/`managementMode` or any code path reading them.

**What tests.** Focused: `Relationship` CRUD (already covered by Phase 2); permission-check helper tests if introduced.

**Migration risk.** None.

**Commit boundary.** One commit: `feat: add Relationship management UI`.

**Rollback plan.** `git revert`. `ProfileKind`/`ProfileManagementMode` still govern all existing behavior untouched.

---

## Phase Summary Table

| Phase | Does | Old fields still present after? | Risk | User-visible |
|---|---|---|---|---|
| 1 | Add Relationship, MeasurementDefinition, MeasurementEntry tables | Yes | None | No |
| 2 | Repository + Engine for new entities | Yes | None | No |
| 3 | Measurement UI (additive, old fields untouched) | Yes | None | Yes |
| 4 | Migrate every read/write site to the new model | Yes (unused) | **Medium** (regression, not data) | No (behavior-preserving) |
| 5 | Remove old fields | No | Low, if #4 verified | No (behavior-preserving) |
| 6 | Goal auto-rollup (optional link) | No | None | Yes |
| 7 | Relationship UI | No | None | Yes |

Phases 1–7 can proceed in order. The former Phase 7 ("deferred, unscheduled legacy migration") from the superseded plan is now Phases 4–5, brought onto the active critical path — this is the direct consequence of Option B and the "no real users" context. **Stop for review before starting Phase 1** — no code has been written for this plan yet.
