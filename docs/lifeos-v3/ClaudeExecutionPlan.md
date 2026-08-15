# LifeOSv3 — Claude Execution Plan

This is the complete implementation plan for the LifeOSv3 UI rebuild. Follow
it in order. **One chunk equals one commit and one review checkpoint. Do not
start the next chunk until the user has reviewed the prior chunk.**

## Read before editing

1. `AGENTS.md` — architecture, persistence, project-file, and test rules.
2. `CLAUDE_HANDOFF.md` — product direction and completed work.
3. `docs/lifeos-v3/MockReferences.md` — approved visual and interaction
   reference.
4. `docs/lifeos-v3/mock-references/` — screen images.

## Global rules

- Work in `LifeOSv3` only. Check `git status` before every chunk.
- Use the existing SwiftData models, repositories, `PlanningService`, and
  progress engines. Do not create a parallel data model.
- Preserve profile identity boundaries. Never resolve data by display name.
- Keep categories, goals, and measurements data-driven; no sport-, subject-,
  or nutrition-name conditionals.
- New Swift files require explicit Xcode project and `Package.swift`
  registration as described in `AGENTS.md`.
- Build the **LifeOS** scheme from `LifeOS.xcodeproj`, not the `LifeOSCore`
  package scheme.
- Run only focused tests for a changed behavior. Do not repeatedly run the
  full suite.
- Use native SwiftUI, not HTML/CSS. Visual standard: warm ivory canvas, deep
  oxblood action color, serif display headings, SF Pro body, soft white cards,
  generous spacing, and quiet motion.

## Already complete — do not redo

- Shared ivory/oxblood/serif visual foundation.
- Today shell and toolbar styling.
- Today task behavior: leading ring → one-tap completion → automatically
  revealed green check → second tap safely undoes the exact occurrence.
- Goal creation is a three-step guided view built on existing Goal models.
- Approved mock images and the v3 reference guide are committed.

## Chunk 1 — Guided first-time setup

**Primary file:** `LifeOS/Views/RootTabView.swift` (`LifeOSOnboardingView`).

### Build

Replace the old bulk template-selection onboarding with this beginner flow:

1. **What would you like to improve?** Free text, with examples only.
2. **How will you know?** Outcome name, unit/type, target, optional date.
3. **A gentle starting plan.** Show editable suggested tasks and cadence.
4. Finish into the prepared Today screen.

Nutrition may be offered as a default specialist module. It must not silently
create nutrition targets or daily tasks.

### Do not

- Do not create template areas/tasks in bulk before the user approves them.
- Do not change Goal, ResultMeasure, Activity, AppCategory, or profile schema.
- Do not alter Today completion or navigation tabs.

### Acceptance check

- A new profile can get from intent to Today without understanding Areas,
  Plans, measurements, or advanced scheduling.
- The result uses existing Goal/ResultMeasure/GoalAreaContribution persistence.
- The simulator matches the setup mock’s hierarchy and spacing.

### Stop and report

Commit only this chunk. Report changed files, build result, focused test result,
commit hash, and screenshots of all setup steps. Stop for review.

## Chunk 2 — Quick Add Task

**Primary file:** `LifeOS/Views/AddActivityView.swift`.

### Build

Make the initial task form shallow:

1. Task title.
2. Plan/Area.
3. When (one-time or clear, intentional recurrence).
4. Create.

After creation, show optional details for measurements, targets, tags,
reminders, duration, and advanced recurrence.

### Do not

- Do not default a new task to every day at 6 pm.
- Do not expose the full advanced form before creation.
- Do not create a new task model or bypass existing schedule persistence.

### Acceptance check

- A basic task can be created in seconds.
- It appears on the correct profile’s Today screen and is linked to its Area
  and supporting goal through existing relationships.
- Advanced details remain available after creation.

### Stop and report

One commit, focused creation/scheduling tests, and simulator screenshots.
Stop for review.

## Chunk 3 — Nutrition specialist experience

**Primary files:** current Nutrition dashboard, meal logging, water, and body
tracking views only as necessary.

### Build

- Show configurable daily protein, calories, carbs, fat, and water targets.
- Lead with current value and remaining amount; percentage is secondary.
- Keep meal logging fast: template, recent meal, manual entry.
- Keep weight as a separate weekly/trend measure.
- Keep nutrition separate from generic task-session progress.

### Do not

- Do not change NutritionEngine, meal/water/weight ownership, or data schema
  unless required and reviewed.
- Do not claim that adherence caused weight change.
- Do not show nutrition as “0 of N sessions” or “Behind.”

### Acceptance check

- Logging a meal/water entry immediately updates that profile’s daily total and
  remaining amount.
- Parent and child data stay isolated.
- Macro values are internally coherent or clearly validated before saving.

### Stop and report

One commit, focused nutrition/profile tests, and screenshots. Stop for review.

## Chunk 4 — Plans, task details, and Schedule

**Primary files:** existing Plans/category views, `TaskDetailView`, and
`WeeklyScheduleView`.

### Build

- Apply shared v3 components and visual hierarchy.
- Make Plan → Goal → Task relationships understandable without exposing
  database vocabulary.
- Keep task detail for edit, reschedule, skip, optional measurement logging,
  and history.
- Make Schedule a calm week view with time-ordered task cards.

### Do not

- Do not reintroduce Start/Finish/Skip menus on Today.
- Do not call a new plan “Behind” at zero evidence.
- Do not modify `PlanningService` casually.

### Acceptance check

- Today stays the fast execution surface.
- Details own exceptional actions.
- Plans explain what tasks support without forcing extra setup.

### Stop and report

One commit, focused schedule/detail tests, and screenshots. Stop for review.

## Chunk 5 — Progress and weekly review

**Primary files:** existing Progress and goal dashboard views.

### Build

- Present weekly task adherence beside observed outcome trend.
- Make “on pace”, “needs attention”, and “not enough evidence” neutral and
  descriptive.
- Support generic goals using ResultMeasure; do not create special sports or
  school dashboards.
- Nutrition review shows target adherence and weight trend side by side.

### Do not

- Do not imply that one week’s tasks caused a physical or academic result.
- Do not replace data engines or modify historical snapshots.

### Acceptance check

- A user can understand what they did, what changed, and what to do next.
- Empty/new plans use calm copy rather than failure language.

### Stop and report

One commit, focused progress tests, and screenshots. Stop for review.

## Final integration review

After all five reviewed commits:

1. Build the LifeOS scheme.
2. Run the focused unit/component/UI tests that cover changed journeys.
3. Manually check parent/child switching, first-time setup, quick add,
   one-tap completion/undo, nutrition targets/logging, and weekly review.
4. Send commit list, remaining warnings, known limitations, and screenshots
   for final review.

