# LifeOS Nutrition Module — Integration Plan (v1)

STATUS: PLAN ONLY — DO NOT CODE YET

Companion to [NUTRITION_MODULE_DESIGN_V1.md](NUTRITION_MODULE_DESIGN_V1.md) (approved architecture) and the mock-screens artifact linked there. This document maps that approved design onto the actual current codebase: what exists today, what gets reused, what gets replaced, and the concrete file list for the build phase.

## 1. What Exists Today

LifeOS already has three tracker screens that predate the Nutrition module design — `FoodTrackerView.swift`, `WeightTrackerView.swift`, `SportTrackerView.swift` — all pre-dating the repository-pattern convention and untouched during the V2 measurement refactor per CLAUDE.md.

**`FoodTrackerView.swift`** — profile-global food/nutrition tracker.
- `@Query FoodEntry` + `@Query WeightEntry`, filtered in-memory by `profile.id`. No repository — talks directly to `@Environment(\.modelContext)`.
- Renders a calorie ring (`SignatureProgressRing` + `ProgressEngine.nutritionTotals`), a macro grid (protein/carbs/fat vs. `Profile` goal fields), a per-`MealType` meal list, and a weight summary card.
- `AddFoodEntryView`/`EditFoodEntryView` — plain Forms constructing `FoodEntry` directly.
- `WeeklyMealPlanView` — a 7-day meal planner that reuses **the same `FoodEntry` model**, distinguished only by a string sentinel (`nutritionSource == "Meal Plan"` / computed `isMealPlanItem`). "Logging" a planned meal creates a second, separate `FoodEntry` row with `nutritionSource: "Planned meal"`.

**`WeightTrackerView.swift`** — profile-global weight tracker.
- `@Query WeightEntry`, filtered by profile id, no repository.
- Trend chart (Swift Charts, moving average via local `WeightTrendEngine`), delta-to-goal via `Profile.weightGoalKilograms`, history list with swipe-to-delete, `AddWeightEntryView`/`EditWeightEntryView` Forms.

**`SportTrackerView.swift`** — per-`AppCategory` sport session tracker (not food/weight-coupled; included here only for pattern comparison). `@Query SportEntry` filtered by profile id **and** category id, no repository. Session kind/duration/reps/effort/soreness fields.

**Models (`LifeOS/Models/Models.swift`):**

```swift
enum MealType { case breakfast, lunch, dinner, snack, drink }

@Model final class FoodEntry {
    static let mealPlanSource = "Meal Plan"
    var id: UUID
    var profile: Profile?
    var date: Date
    var mealTypeRaw: String            // → mealType: MealType
    var name: String
    var calories, proteinGrams, carbohydrateGrams, fatGrams, waterMilliliters: Double
    var note: String
    var barcode: String?
    var nutritionSource: String        // "Manual" | "Meal Plan" | "Planned meal" — sentinel, not enum
    @Attribute(.externalStorage) var photoData: Data?
    var servings: Double = 1
    var isMealPlanItem: Bool { nutritionSource == Self.mealPlanSource }   // computed
}

@Model final class WeightEntry {
    var id: UUID; var profile: Profile?; var date: Date
    var kilograms: Double; var note: String
}
```

`Profile` carries nutrition/weight **goals directly as fields** (no separate goal model today):
```swift
var weightUnitRaw: String = WeightUnit.kilograms.rawValue
var weightGoalKilograms: Double?
var calorieGoal: Double = 2200
var proteinGoalGrams: Double = 120
var carbohydrateGoalGrams: Double = 250
var fatGoalGrams: Double = 70
var waterGoalMilliliters: Double = 2500
```

**Shared logic:** `Engine/ProgressEngine.swift` has `NutritionTotals` + `nutritionTotals(profile:date:entries:calendar:)`, explicitly added to de-duplicate identical logic that used to live independently in `FoodTrackerView` *and* `TodayTimelineView`'s plan-card nutrition snapshot. `TodayTimelineView` is therefore a second live consumer of `FoodEntry` beyond the tracker itself.

**No repository exists** for any of Food/Weight/Sport — all three views bypass the `XRepository` pattern entirely, unlike `CalendarRepository`/`MeasurementRepository`/`RelationshipRepository`.

**`MeasurementDefinition`/`MeasurementEntry`** (Models.swift, Engine/MeasurementRepository.swift) are confirmed dormant — explicitly commented as "inert... not yet wired into any Repository, Engine, or View" — and structurally Activity-scoped (`MeasurementDefinition.activity: Activity?`, entries link to `ActivitySession`). This confirms the design doc's reasoning: they're the wrong shape for Profile-scoped, always-on body metrics, which is why `BodyMetricDefinition`/`BodyMetricEntry` were designed as parallel siblings rather than reused. The one thing worth carrying over structurally (not by reference) is the snapshot pattern (`nameSnapshot`/`unitSnapshot`), which the design doc already does for `MealEntry` and `BodyMetricEntry`.

**Routing:** `AppCategory` has an `AreaTrackingKind` enum with a `.nutrition` case (string-heuristic classification, e.g. `normalizedName.contains("nutrition")`) and `SeedData.swift` seeds a `"Nutrition"` `AppCategory` (icon `fork.knife`, pillar `.nutrition`). This is very likely what currently routes an Area into `FoodTrackerView` — **needs a targeted grep on `trackingKind` usage in root/hub navigation before implementation** to confirm the exact routing hook the new module needs to take over.

**Registration:** Existing tracker files are registered as individual `PBXFileReference`/`PBXBuildFile`/Sources entries in `project.pbxproj` (per CLAUDE.md's explicit-registration convention); `Package.swift` covers them via its glob-style `LifeOS` source path, no per-file entry needed there.

## 2. What to Reuse

| Existing asset | Reuse as |
|---|---|
| `ProgressEngine` pattern (aggregation helper struct + static func) | Template for a new `NutritionEngine.dailyTotals(...)` and `BodyTrackingEngine` equivalent — same shape, new inputs (`MealEntry`/`WaterEntry`/`BodyMetricEntry` instead of `FoodEntry`). |
| `SignatureProgressRing`, `ColorToken`, `LifeOSSpacing`/`LifeOSRadius`, `ImprovementPillar.nutrition.gradient` | Directly, unchanged — Dashboard hero ring and card chrome per the mockups. |
| `MeasurementDefinition`/`MeasurementEntry`'s snapshot pattern (`nameSnapshot`/`unitSnapshot`) | Structural pattern only, copied into `BodyMetricEntry`/`MealEntry.sourceTemplateNameSnapshot` — already reflected in the design doc. |
| `XRepository` protocol shape (`hasChanges`, `@discardableResult func save()`) from `CalendarRepository`/`MeasurementRepository` | Template for the new `NutritionRepository` and `BodyTrackingRepository`. |
| `WeightTrendEngine` (moving-average logic in `WeightTrackerView.swift`) | Reusable logic, relocate into `BodyTrackingEngine`/repository rather than living inline in a View. |
| Swift Charts trend chart from `WeightTrackerView` | Reusable as the Body Tracking trend visual, restyled per the mockups but same charting approach. |
| `AreaTrackingKind.nutrition` routing hook | Reuse the routing *seam* (an Area still routes to "the nutrition screen") but repoint its destination from `FoodTrackerView` to the new Nutrition module entry screen. |
| `ProfileGoalsView`'s pattern of an editable goals form | Reusable as the shape for editing `NutritionGoal`, but reading/writing the new model instead of `Profile` fields directly. |

## 3. What to Replace

| Existing | Replaced by | Why |
|---|---|---|
| `FoodEntry` (`@Model`) | `MealEntry` + `FoodEntry` (new shape, owned by `MealEntry`/`MealTemplate`) + `NutritionValue` | Current `FoodEntry` conflates a whole meal and a single food item into one flat model, and conflates "planned" vs. "actual" via a string sentinel (`nutritionSource`) instead of separate types. The approved design's `MealTemplate`/`MealEntry` split replaces both problems at once. |
| `FoodTrackerView.swift` (whole file) | `NutritionDashboardView`, `MealLoggingView`, `AddEditMealView`, `MealTemplatesView`, `NutritionProgressView`, `QuickActionSheet` | One monolithic tracker view becomes five purpose-built screens per the approved mockups; old view's inline Forms are replaced by the new Add/Edit Meal screen. |
| `WeeklyMealPlanView` + `AddPlannedMealView`/`EditPlannedMealView` (meal planning via sentinel-tagged `FoodEntry`) | Superseded by `MealTemplate` (repeat-meal use case) + Recent Meals (one-off repeat use case) | The design's "Recent Meals" and "Templates" together cover what meal-planning was approximating with tagged `FoodEntry` rows, more explicitly and without the sentinel hack. Full-day/weekly planning is explicitly out of v1 scope (design doc §7 future scope), so this is a straight removal, not a reimplementation. |
| `WeightEntry` (`@Model`) | `BodyMetricEntry` (with `BodyMetricDefinition` for "Weight") | Weight becomes one instance of the data-driven Body Tracking model instead of its own bespoke type, per approved decision #5. |
| `WeightTrackerView.swift` (whole file) | `BodyTrackingView` (weight-primary, Height/Body Fat %/custom metrics secondary, per mockup Screen 06) | Same visual job, rebuilt against `BodyMetricDefinition`/`BodyMetricEntry` instead of `WeightEntry`. |
| `Profile.calorieGoal`/`proteinGoalGrams`/`carbohydrateGoalGrams`/`fatGoalGrams`/`waterGoalMilliliters`/`weightGoalKilograms` (fields on `Profile`) | `NutritionGoal` (calorie/macro/water targets) + a `BodyMetricDefinition`-linked target for weight | Goals move off `Profile` into their own model so they can be created/edited/versioned independently and linked from `ResultMeasure`, consistent with decision #1 (no Activity/Profile-field coupling) and §5's direct linkage design. `Profile.weightUnitRaw`/`WeightUnit` can stay — unit preference is a legitimate Profile-level setting, not a nutrition entity. |
| `ProfileGoalsView`'s nutrition/weight-goal editing fields | New `NutritionGoal` edit screen + Body Tracking's own goal editing | `ProfileGoalsView` currently mixes these with other profile-level goal fields; the nutrition/weight portions move out, whatever remains (if anything non-nutrition) stays. |

**Not replaced / left alone:** `SportTrackerView.swift`, `SportEntry` — unrelated to Nutrition, no design decision calls for touching it. `MeasurementDefinition`/`MeasurementEntry` stay exactly as they are (still dormant, still Activity-scoped) — Nutrition gets siblings, not a takeover.

## 4. What New Files Are Required

Model layer (new file, e.g. `LifeOS/Models/NutritionModels.swift`, to keep the growing `Models.swift` from absorbing another ~6 types — final filename/placement is a build-time call):
- `NutritionGoal`
- `MealTemplate`
- `MealEntry` (replaces `FoodEntry`'s meal role)
- `FoodEntry` (new shape — owned by `MealEntry`/`MealTemplate`; name collision with the old model is intentional replacement, not coexistence)
- `NutritionValue` (struct)
- `WaterEntry`
- `BodyMetricDefinition`
- `BodyMetricEntry`

Repository layer (`LifeOS/Engine/`):
- `NutritionRepository.swift` (meals, templates, water — `XRepository`-shaped)
- `BodyTrackingRepository.swift` (`BodyMetricDefinition`/`BodyMetricEntry`, including per-Profile seeding of Weight/Height/Body Fat % defaults)
- `NutritionEngine.swift` (or extend `ProgressEngine.swift`) — daily totals aggregation, consistency-day calculations for Progress, replacing `ProgressEngine.nutritionTotals(profile:date:entries:[FoodEntry])`'s signature with the new entities.

View layer (`LifeOS/Views/`, replacing `FoodTrackerView.swift`/`WeightTrackerView.swift`):
- `NutritionDashboardView.swift`
- `QuickActionSheet.swift`
- `MealLoggingView.swift`
- `AddEditMealView.swift`
- `MealTemplatesView.swift`
- `BodyTrackingView.swift`
- `NutritionProgressView.swift`
- Small subview files as needed (e.g. a shared `MacroBarRow`, `FoodStepperRow`) — final split is an implementation-time call, not an architecture decision.

Model/schema registration:
- Add all eight new types to `LifeOSSchemaV1.models` in `SchemaVersioning.swift` (pre-release exception, per that file's own documented carve-out — worth reconfirming LifeOS still hasn't shipped before relying on this).
- Remove `FoodEntry` (old shape), `WeightEntry` from the roster once their Views are removed and any data-migration question is resolved (see Open Questions).
- Register every new Swift file as explicit `PBXFileReference`/`PBXBuildFile`/Sources entries in `project.pbxproj`, `plutil -lint` after; `Package.swift` needs no per-file change (glob-covered).

Goal-linkage change (extends existing type, not a new file):
- `ResultMeasure` gains `linkedNutritionMetricID`/`NutritionMetricKind` and `linkedBodyMetricDefinitionID` optional fields (design doc §5) — edited in place in `Models.swift`, and `GoalProgressEngine`/`EditGoalViews.swift`/`ImprovementDashboardView.swift`'s Result-source picker gain a third/fourth source option alongside Manual/Activity-measurement.

## 5. Open Questions Before Implementation

1. **Data migration for existing `FoodEntry`/`WeightEntry` rows** — CLAUDE.md states no production users yet, which per this project's convention means correctness of architecture outranks backward compatibility, i.e. it's fine to not migrate old rows. Confirm that still holds before the old models are deleted rather than deprecated.
2. **`TodayTimelineView`'s plan-card nutrition snapshot** — a second consumer of `FoodEntry`/`ProgressEngine.nutritionTotals` besides the tracker itself; needs its own read-path update to the new `NutritionEngine`, not just a `FoodTrackerView` swap.
3. **`AreaTrackingKind.nutrition` routing** — confirm exactly where this routes today (grep root/hub navigation for `trackingKind`) so the new Nutrition module can take over the same seam cleanly.
4. **`ProfileGoalsView` scope** — confirm what, if anything, remains in that view once nutrition/weight goal fields move out; may become a much smaller view or may be removable entirely depending on what else it edits.

No code has been written or modified for this plan — it is scoped entirely against the current repository state as of this analysis.
