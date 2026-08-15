# LifeOS — Project Context

Read this first in any new session before touching UI/UX. It exists so a fresh
session doesn't have to re-derive the stack, architecture, or in-flight work
from scratch.

## Stack

- SwiftUI + SwiftData (iOS 17+ target), `@Model` classes, `ModelContext`, `@Query`.
- Xcode project uses **explicit** `PBXFileReference`/`PBXBuildFile`/group/`Sources`-phase
  entries in `project.pbxproj` (not synchronized folder groups) — every new Swift file
  needs manual 4-point registration there, plus adding it to `Package.swift`'s
  `sources:` list for the headless SPM test target (`LifeOSCorePackageTests`, run via
  `swift test`). Validate `project.pbxproj` edits with `plutil -lint` after each change.
- Repository pattern: `protocol XRepository { var hasChanges: Bool; func insert...(); 
  @discardableResult func save() -> Bool }` + `@MainActor final class SwiftDataXRepository`.
  See `Engine/CalendarRepository.swift`, `Engine/MeasurementRepository.swift`,
  `Engine/RelationshipRepository.swift`.
- View → ViewModel → Repository → SwiftData layering exists today only for the Today
  screen; most other views talk to `@Environment(\.modelContext)` and `@Query` directly.
- `PlanningService` is the single schedule-calculation engine — protected, never modified
  casually.
- `ProgressEngine` / `CategoryProgressEngine` (`GoalProgressEngine`) compute progress —
  daily target-vs-actual, category rollups, and Goal status. `ProgressMetric` is the
  generic progress type (title/current/target/unit/status/destination) used to unify
  Today/Progress displays.
- Historical snapshot pattern: records that reference a mutable definition (e.g.
  `MeasurementEntry` → `MeasurementDefinition`) also carry `nameSnapshot`/`typeSnapshot`/
  `unitSnapshot` copied at creation time, so they stay interpretable even if the
  definition is later renamed or deleted.
- No production users yet — migrations are handled by adding new types directly to
  `LifeOSSchemaV1`'s roster in `Models/SchemaVersioning.swift` rather than defining
  versioned `V2`/`V3` schemas or `MigrationStage` ceremony.

## Domain model (current)

`Profile` → `AppCategory` (Area, hierarchical via `parentCategoryID`/data-driven
`ImprovementTemplates.swift`) → `Activity` (a Task/Discipline) → `CalendarItem`
(scheduled occurrence) → `ActivitySession` (a completed/logged instance, `recordedValue`
legacy field) → `MeasurementDefinition`/`MeasurementEntry` (per-Activity, user-defined
named measurements like "Ground Balls", "Catches" — additive, coexists with legacy
`Activity.targetValue`/`targetUnit`). `Goal` → `ResultMeasure` (primary/supporting,
manual check-ins via `ResultEntry`, or now linked to a `MeasurementDefinition` via
`linkedMeasurementDefinitionID` for automatic, generic progress) → `GoalAreaContribution`
(links a Goal to supporting Areas). `Relationship` model exists (pending/active/revoked)
but is not yet wired into any UI — out of scope until explicitly requested.

## Key views (LifeOS/Views/)

- `RootTabView.swift` — tab container.
- `TodayTimelineView.swift` — Today/home screen, MVVM-boundaried (the one screen with a
  real ViewModel layer).
- `WeeklyScheduleView.swift` — calendar/scheduling UI (built on `PlanningService`).
- `AddActivityView.swift` / `EditTaskView.swift` — create/edit a Task, including its
  optional `MeasurementDefinition`s (additive "Measurements" Form section).
- `AddWhatHappenedView.swift` — manual/unplanned one-off logging (always creates a new
  Activity, so no pre-existing measurement definitions to load).
- `RecordActualView.swift` — the "Done"/"Finish" flow from a scheduled `CalendarItem`.
  Shows the legacy target Stepper (unchanged) plus a "Measurements" section fed by that
  Activity's `MeasurementDefinition`s. Measurement inputs are raw `String` state, never
  prefilled — blank means not recorded, `MeasurementEntry` is only created for
  non-blank, successfully-parsed values.
- `DailyProgressView.swift` — "Task Progress" screen: three independent sections —
  legacy target-vs-actual (`ProgressBarRow`), new per-measurement progress
  (`MeasurementProgressRowView`, never blended across measurements/units), and 7-day
  trend. Each section only renders if it has data; the empty state only shows when all
  are empty.
- `AddImprovementCategoryView.swift` — Area/Discipline template picker, data-driven via
  `Engine/ImprovementTemplates.swift` (`parentTemplateID` hierarchy — e.g.
  Sports → Baseball, Music → Guitar — never hardcoded per-sport logic).
- `ImprovementDashboardView.swift` — Goals dashboard + Goal detail. Contains
  `AddGoalView` (create Goal + primary Result Measure), `AddResultMeasureView` (add a
  supporting Result Measure), `AddResultEntryView` (manual check-in entry). Both
  Add-measure flows have a "Result source" segmented picker: Manual check-in vs Activity
  measurement (picks a compatible non-text `MeasurementDefinition` from the profile).
- `EditGoalViews.swift` — `EditGoalView`, `EditResultMeasureView` (same Result-source
  picker, can flip an existing measure between manual/linked), `EditResultEntryView`.
- `FoodTrackerView.swift` / `WeightTrackerView.swift` / `SportTrackerView.swift` —
  Nutrition/body-metric tracking, deliberately not touched during the V2 measurement
  refactor (paused at a real migration-safety gate).
- `ProfileManagerView.swift` / `ProfilePicker.swift` / `ProfileGoalsView.swift` —
  Profile management and per-profile Goal views.
- `BackupCenterView.swift` — export/import.

## Styling (DesignSystem.swift, ColorToken.swift)

- `LifeOSSpacing` (xs 4 → xxl 32) and `LifeOSRadius` (sm 12 → xl 28) are the shared
  layout tokens — use these instead of hardcoded numbers in new UI.
- `Animation.lifeOSTap` (spring 0.32/0.72) and `.lifeOSReveal` (spring 0.5/0.82) are the
  two standard motion curves.
- `ColorToken.color(for:)` maps a stored string (e.g. `"orange"`, `"blue"`) to a SwiftUI
  `Color` — Areas/Profiles store a `colorToken: String`, never a raw `Color`, so they
  survive Codable/persistence and stay user-customizable.
- `ImprovementPillar` (physical/sport/nutrition/learning/life) has a fixed two-color
  `LinearGradient` (topLeading → bottomTrailing) and SF Symbol per pillar — gradients
  are reserved for aggregate/hero views only, so a user's custom per-Area `colorToken`
  is never silently overridden by a pillar gradient.
- `SignatureProgressRing` is the shared circular-progress component: a dimmed full-circle
  track (`Color.primary.opacity(0.08)`) plus a gradient-stroked, rounded-cap trim arc,
  with an optional blurred "glow" duplicate arc for motion emphasis (skipped when
  `accessibilityReduceMotion` is on). Progress animates in via `.lifeOSReveal`, exposes
  an accessibility value as a rounded percentage.
- Section pattern in Forms: plain `Section("Title")` for simple groups, or
  `Section { ... } header: { Text(...) } footer: { Text(caption).font(.caption) }` when
  a short explanatory caption is needed below the fields (e.g. "Leave blank to skip a
  measurement").
- No custom design-system component library beyond the above — most screens are plain
  SwiftUI `Form`/`List`/`ScrollView` + system materials, relying on `ColorToken` for
  brand color and `LifeOSSpacing`/`LifeOSRadius` for consistent spacing/corner radii.

## Working conventions established this project

- No production users yet: prioritize correct architecture over backward compatibility;
  behavior must be preserved, the underlying data model does not have to be.
- Additive-first: new fields get default values in `init()` so existing call sites keep
  compiling; old fields (`Activity.targetValue`/`targetUnit`, `ActivitySession.recordedValue`)
  stay in place until an explicit future removal instruction.
- Every "Run"/"Task" unit of work in this project ends with an explicit
  commit-or-not instruction from the user — never assume; show changed files and wait.
- Never hardcode per-domain logic (no `if sport == "Baseball"` branches) — categories,
  disciplines, and measurements are all data-driven so Baseball/Guitar/Coding/etc. use
  identical code paths.
- Token/effort discipline: don't run the full test suite unless asked; the user builds
  and tests locally in Xcode; focus on the minimum diff that satisfies the explicit ask.
