# LifeOSv3 Approved Mock References

These images are the visual reference for the UI rebuild. Implement them as
native SwiftUI screens: match hierarchy, spacing, typography, card treatment,
and interaction intent—not static pixel copies. Use dynamic type, safe areas,
and accessibility labels.

## Non-negotiable interaction rules

- **Today completion is one tap.** The circle on each task marks it done
  immediately. It must not open Start, Finish, or a measurement form.
- The completion ring/checkmark is the **leading control** in a task row;
  the task icon and title follow it. Do not place the primary completion
  affordance at the trailing edge.
- A second tap on the completed checkmark undoes only that occurrence's
  completion. It must delete evidence by calendar-occurrence identity, never
  by task name, time, or profile name.
- Task detail is for edit, skip, reschedule, and optional measurement logging.
- Nutrition uses specialist daily targets and logs, never generic sessions.
- Do not show a new plan as "Behind" when there is no evidence yet.

## Screen references

| Screen | Reference | Key intent |
| --- | --- | --- |
| Today | [today.png](mock-references/today.png) | Calm daily surface, direct task completion, compact plan snapshots. |
| Plans | [plans.png](mock-references/plans.png) | Areas/plans grouped quietly; primary action is clear. |
| Progress | [progress.png](mock-references/progress.png) | Neutral review of activity and plan-level evidence. |
| Schedule | [schedule.png](mock-references/schedule.png) | Week context and time-ordered tasks. |
| Task details | [task-detail.png](mock-references/task-detail.png) | Secondary actions live here, not on Today. |
| Nutrition | [nutrition.png](mock-references/nutrition.png) | Daily macro/water status and meal logging. |
| One-tap Today detail | [today-one-tap-reference.png](mock-references/today-one-tap-reference.png) | Current target example: a single visible completion circle for each task. |
