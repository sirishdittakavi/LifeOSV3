# LifeOSv3 UI Rebuild — Implementation Handoff

## Product standard

Implement the approved native iPhone direction closely: warm ivory/parchment
surfaces, deep oxblood primary actions, serif display headings, SF Pro body
text, generous spacing, soft bordered cards, and quiet motion. This is a UI
rebuild over the existing engine — do not build a second data model.

The user journey is:

1. First-time setup: user describes what they want to improve.
2. Outcome: user sets the measurement, target, and optional date.
3. Gentle starting plan: user reviews/edits suggested supporting tasks.
4. Today: direct completion, minimal decisions.
5. Optional detail: measurements, tags, reminders, and full scheduling.
6. Nutrition is specialist tracking, not generic task sessions.
7. Weekly review places adherence beside observed outcome; it must not imply
   that effort caused a result.

## Approved mock screens

Read [the mock reference guide](docs/ClaudeMockReferences.md) before touching a
screen. The source images are committed under `docs/mock-references/`, so the
visual standard stays available to every implementation agent.

## Completed in the current commit

- Shared visual tokens: `LifeOSColors`, typography, components, and primary
  button styles now use the ivory/oxblood/serif direction.
- Root navigation tint uses `Color.lifeOSAccent`.
- Today has the warm shell, editorial heading, filled Add button, and one
  **immediate** completion action instead of its previous Start/Finish/Skip
  menu. Optional measurement capture no longer interrupts a completion tap.
- `AddGoalView` is now a three-step guided flow using the existing `Goal`,
  `ResultMeasure`, and `GoalAreaContribution` persistence logic:
  own words -> outcome/target -> supporting plan/check-in.

## Do not change

- `PlanningService` schedule calculation engine.
- Profile ownership/filtering rules or notification ownership routing.
- SwiftData model identity relationships without a specific migration plan.
- The data-driven category approach: never branch on a particular sport,
  school subject, or nutrition target by name.
- Do not edit the same files concurrently with another agent.

## Claude work — do in these small commits

### 1. Replace first-time onboarding

File: `LifeOS/Views/RootTabView.swift` (the private `LifeOSOnboardingView`).

Replace the old bulk template-selection flow. First-time setup should ask for
one free-text improvement, then outcome metric/target/date, then an editable
starter plan. Nutrition may be offered as a default module, but no default
target or daily obligation should be silently created. Reuse current models
and creation services; do not add a parallel onboarding schema.

### 2. Rebuild Quick Add Task

File: `LifeOS/Views/AddActivityView.swift`.

Make the first screen only: task title, plan/area, and when. Create from those
three choices. Put measurements, targets, tags, reminders, duration, and
advanced recurrence behind an explicit "Add details" step after creation.
Avoid a default daily 6 pm obligation. Preserve existing Activity creation and
schedule persistence contracts.

### 3. Specialist Nutrition shell

Files: `LifeOS/Views/NutritionDashboardView.swift`, `MealLoggingView.swift`,
`QuickActionSheet.swift`, and related existing nutrition views only as needed.

Keep meal/water/weight records and NutritionEngine unchanged. Show a daily
target, current value, and remaining amount for configured metrics. Protein is
the primary example; water has the same target/remaining pattern. Keep weight
as a separate trend. Do not show nutrition as generic "sessions".

### 4. Re-skin Plans, Progress, Schedule and task detail

Files: `ImprovementCategoriesView.swift`, `ImprovementDashboardView.swift`,
`WeeklyScheduleView.swift`, `TaskDetailView.swift` / its existing owner.

Apply the shared components rather than local colors. Do not label a plan
"Behind" at zero evidence; use neutral, descriptive copy. Task detail owns
edit, skip, and reschedule; Today remains direct.

### 5. Completion undo — separate behavioral change

Do only after the UI screens above are stable. A second tap on a completed
simple task should safely undo completion. It must restore CalendarItem state
and remove only the matching ActivitySession for that occurrence, with a save
rollback. Add a repository-level operation and focused unit tests; do not
delete sessions by activity name or across profiles.

## Verification

- User should build `LifeOS.xcodeproj` using the `LifeOS` scheme, not the
  `LifeOSCore` package scheme.
- This environment could not complete simulator asset compilation because
  CoreSimulatorService was unavailable; it did not report a Swift source
  error before that environment failure.
- Do not run the full suite repeatedly. Add/run focused tests for completion
  undo, duplicate prevention, profile isolation, and goal/task creation once
  each behavior is implemented. Review visual quality in the simulator.

## Commit discipline

Make one commit per numbered chunk above. Before changing source files, check
the working tree; preserve unrelated user changes. New Swift files require
manual `project.pbxproj` and `Package.swift` registration per `AGENTS.md`.
