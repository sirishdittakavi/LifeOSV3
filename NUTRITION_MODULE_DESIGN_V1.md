# LifeOS Phase 3 — Nutrition Module Design (v1)

STATUS: APPROVED (architecture) — DO NOT CODE YET

## Approved Decisions (supersede earlier draft)

1. Nutrition is a **specialised, standalone LifeOS module** — it must not be modeled as an `Activity` or a synthetic/system-managed `Activity`. No coupling to `Activity`/`CalendarItem`/`ActivitySession` or to `MeasurementDefinition`'s Activity-scoped ownership.
2. `MealEntry` preserves the history concept, but supports normal user editing for corrections — users should not have to create a new record to fix a typo'd gram count. See §4a for exactly which fields are immutable vs. editable and how the edit is audited.
3. Meal Templates are a core v1 feature (full CRUD), not a stretch goal.
4. Weight/Height/body measurements are modeled separately from daily nutrition entries — different cadence, different screen, different repository.
5. Body Tracking is **data-driven**, not a fixed enum: `BodyMetricDefinition` (user/system-defined metric, e.g. "Weight", "Height", "Body Fat %", extensible to future custom metrics) + `BodyMetricEntry` (historical value against a definition), mirroring the existing `MeasurementDefinition`/`MeasurementEntry` pattern but scoped to Profile, not Activity.
6. Water remains a simple Nutrition-scoped daily entry (`WaterEntry`), not folded into Body Tracking.
7. Barcode scanning / AI photo recognition are **not implemented now** — extension points only (see §6).
8. No code yet — this document is the frozen architecture to implement against once you give the go-ahead.

## 1. User Journeys

**Journey A — Daily logging (primary loop)**
Open app → Today tab (existing) shows a Nutrition summary tile → tap into Nutrition Dashboard → tap meal slot (Breakfast/Lunch/Dinner/Snack) → pick from Templates or "Log manually" → confirm → dashboard updates immediately.

**Journey B — Template creation (investment loop)**
User logs the same breakfast 3x manually → after logging, sees "Save as Template" prompt → names it → template appears in Templates list → future logging becomes one-tap.

**Journey C — Body check-in (separate cadence)**
Independent of meals — user opens Body Tracking (weekly-ish) → logs Weight (+ optional Body Fat %) → sees trend line vs. last entry and 30-day trend.

**Journey D — Weekly review**
User opens Nutrition Progress → sees protein/calorie consistency (days hit target / days logged), weight trend, template usage. Ties back into `Goal`/`ResultMeasure` if the user has linked a nutrition Goal (e.g. "Hit 150g protein 5x/week").

## 2. Recommended Screens

```
Nutrition
├── Dashboard (Today)        — status, ring/bar progress, meal checklist
├── Meal Logging             — per-meal entry, template picker, manual/quick-macro entry
├── Meal Templates           — list/create/edit/duplicate/delete
├── Body Tracking            — weight/height/body-fat history + trend
└── Progress                 — consistency %, trends, links to Goals
```

## 3. UX Flow (text diagram)

```
Today Tab ──(nutrition tile)──▶ Nutrition Dashboard
                                       │
                    ┌──────────────────┼───────────────────┐
                    ▼                  ▼                    ▼
             Tap meal slot      Body Tracking tab      Progress tab
                    │
        ┌───────────┼────────────┐
        ▼           ▼            ▼
  My Templates   Manual entry  Quick macro entry
   (1-tap use)   (full food    (P/C/F only,
                  detail form)  no name needed)
        │           │            │
        └─────▶ MealEntry created (date/time/type/source) ─▶ Dashboard refresh

Template management (separate entry point):
Templates List ─▶ [+] Create ─▶ add FoodEntries ─▶ save
                ─▶ swipe: Edit / Duplicate / Delete
```

## 4. Data Model Proposal

New Nutrition-specific `@Model` types (mirroring existing repo/snapshot conventions):

```
NutritionGoal
- id, profileID
- proteinTargetG, carbsTargetG, fatTargetG, calorieTarget, waterTargetML
- createdAt, updatedAt

MealTemplate
- id, profileID, name, mealTypeDefault (optional)
- foodEntries: [FoodEntry] (owned, reusable snapshot list)
- createdAt, updatedAt

MealEntry                          — the historical record (editable — see §4a)
- id, profileID
- mealType: .breakfast/.lunch/.dinner/.snack
- recordedAt (date/time actually eaten), createdAt, updatedAt
- sourceTemplateID: UUID? (nil if manual)
- sourceTemplateNameSnapshot: String?  ← snapshot pattern, survives template edits/deletes
- foodEntries: [FoodEntry]
- totals: NutritionValue (denormalized cache, recomputed on every edit)
- lastEditedAt: Date?               ← nil until first edit; §4a
- editCount: Int                    ← simple audit counter, default 0

FoodEntry                          — one food item, belongs to a MealEntry OR MealTemplate
- id, name, servingSize, servingUnit
- nutrition: NutritionValue

NutritionValue                     — value type (struct), not a @Model
- proteinG, carbsG, fatG, calories
- (future-proof: optional fiberG, sugarG, sodiumMg = nil in v1, unused but present)

WaterEntry                         — simple daily Nutrition entry, own history
- id, profileID, recordedAt, amountML

BodyMetricDefinition                — data-driven, mirrors MeasurementDefinition but Profile-scoped
- id, profileID, name (e.g. "Weight", "Height", "Body Fat %"), unit
- isSystemDefault: Bool (Weight/Height/Body Fat % seeded per profile; user can add custom metrics)
- createdAt, updatedAt

BodyMetricEntry                     — historical value against a definition
- id, profileID, bodyMetricDefinitionID
- nameSnapshot, unitSnapshot        ← snapshot pattern, survives definition rename/delete
- value, recordedAt, createdAt, updatedAt
```

### 4a. MealEntry: immutable vs. editable fields, and audit handling

Editing is a normal, expected user action (fixing a serving size, correcting a food name, adjusting the meal type after the fact) — it must not require deleting and recreating the record, and it must not be blocked or ceremony-laden.

**Immutable (set once, at creation, never changes):**
- `id`
- `profileID`
- `createdAt`
- `sourceTemplateID` / `sourceTemplateNameSnapshot` — this is a snapshot of *what was used to create the entry*; editing the entry's foods afterward doesn't rewrite what template it came from. (If the user removes/replaces all food entries from a template-sourced meal, the entry simply keeps its original template provenance — it doesn't get un-attributed.)

**Editable (normal user corrections, in place):**
- `mealType`
- `recordedAt` (e.g. user logged lunch under "Dinner" by mistake, or wants to backdate the time)
- `foodEntries` (add/remove/edit individual `FoodEntry` items, including their `nutrition` values)
- `totals` — always a recomputed cache, never hand-edited; recomputes automatically whenever `foodEntries` changes

**How this preserves the history concept without per-edit ceremony:**
- History here means *"the fact that this meal happened, when, and roughly what was in it, is durable and never silently disappears from trends"* — not *"every keystroke is a separate immutable row."* A `MealEntry` is one row per real-world meal; editing it corrects that row rather than fragmenting one meal into several ghost records.
- `updatedAt` (already on the model) advances on every edit — standard SwiftData-adjacent audit convention already used elsewhere in the project (e.g. `MealTemplate`), nothing new.
- `lastEditedAt` + `editCount` are a lightweight, always-visible audit signal (e.g. Meal Logging can show a small "edited" badge on a modified entry) without needing a separate edit-log table. This matches the project's "no premature abstraction" convention — a full field-level diff/version-history table is not justified for v1 and isn't precluded later if it becomes a real ask.
- What is **not** allowed: deleting a `MealEntry` outright is a distinct, explicit destructive action (with confirmation), separate from editing — deletion removes the row from trends entirely, whereas editing keeps the day's nutrition history intact and merely corrects it. This mirrors how `RecordActualView` treats corrections vs. how deletion is treated elsewhere in the app.
- `BodyMetricEntry` and `WaterEntry` get the same treatment for consistency (editable value/recordedAt, immutable id/profileID/createdAt, `updatedAt` tracks edits) — a body-weight or water entry typo is just as normal a correction as a meal one.

**Reuse from existing LifeOS models:**
- `Profile` — all nutrition entities scope by `profileID`, same as everything else.
- `ColorToken` / `LifeOSSpacing` / `LifeOSRadius` / `SignatureProgressRing` — dashboard rings and cards reuse existing design system, no new visual primitives.
- Snapshot pattern (`nameSnapshot`/`unitSnapshot`) — reused for `MealEntry.sourceTemplateNameSnapshot` and `BodyMetricEntry`, same rationale as `MeasurementEntry`'s snapshots surviving a renamed/deleted `MeasurementDefinition`.
- Repository pattern — `NutritionRepository` (meals/templates/water), `BodyTrackingRepository` (`BodyMetricDefinition`/`BodyMetricEntry`), same `hasChanges`/`save()` shape as `MeasurementRepository`.
- `ProgressMetric` — Nutrition Progress and Body Tracking trend both produce `ProgressMetric`s so they reuse the exact same rendering code Today/Progress already use elsewhere.
- The **pattern** of `MeasurementDefinition`/`MeasurementEntry` (definition + snapshot-carrying entry, data-driven rather than enum-driven) is reused conceptually for `BodyMetricDefinition`/`BodyMetricEntry` — but as a **parallel, Profile-scoped sibling type**, not the same `@Model` reused across two owners. This keeps Nutrition fully decoupled from `Activity`.

**Should NOT be shared:**
- `Activity`/`CalendarItem`/`ActivitySession` — meals and body metrics are not scheduled tasks with Start/Finish states, and per decision #1 nutrition must not be modeled as an Activity or synthetic Activity. `MealEntry` and `BodyMetricEntry` are top-level historical records with no Activity ownership.
- `MeasurementDefinition` itself — reserved for per-Activity measurements (Ground Balls, Catches, etc). Nutrition and Body Tracking get their own definition/entry types (`NutritionGoal` for targets, `BodyMetricDefinition`/`BodyMetricEntry` for body metrics) rather than piggybacking on it.

## 5. Connection to Goals & Measurements

Since Nutrition must not couple to `Activity`/`MeasurementDefinition`, Goal linkage needs its own direct path rather than reusing `linkedMeasurementDefinitionID`:

- Add a `linkedNutritionMetricID` (or a small `enum NutritionMetricKind { protein, carbs, fat, calories, water }`) option to `ResultMeasure`, parallel to `linkedMeasurementDefinitionID` — a Goal's Result Measure can point at a `NutritionGoal` macro/water field, and `GoalProgressEngine` reads today's `MealEntry`/`WaterEntry` totals the same way it reads `MeasurementEntry` totals today, without `MeasurementDefinition` being involved.
- Similarly, add a `linkedBodyMetricDefinitionID` option to `ResultMeasure` so a Goal ("Lose 5kg") can link directly to a `BodyMetricDefinition` ("Weight") and read `BodyMetricEntry` history/trend for progress — again a sibling linkage, not a repurposed `MeasurementDefinition` link.
- `DailyProgressView`'s macro/water rings and Body Tracking's trend rows are new, Nutrition-owned row views that consume `NutritionGoal`/`WaterEntry`/`BodyMetricEntry` directly, styled with the same `ProgressBarRow`/`MeasurementProgressRowView`-style components but reading from Nutrition-native data rather than `MeasurementEntry`.

## 6. Future AI/Barcode Architecture Considerations (not built now)

- `FoodEntry` should carry an optional `externalSourceID`/`externalSourceType` (nil in v1) so a future barcode/DB lookup can populate fields without a schema migration — additive, matches project convention.
- Keep `NutritionValue` as a plain struct (not tied to `FoodEntry`'s identity) so AI-photo-estimation can produce a `NutritionValue` and hand it to the same entry-creation path manual entry uses.
- Template engine's "food list + totals" shape is exactly what a future "AI parses your photo into food items" flow would need to populate — no rework required.

## 7. v1 Scope vs Future Scope

**v1 (build now):** Dashboard, manual meal logging, quick-macro entry, Meal Templates (full CRUD), Body Tracking (`BodyMetricDefinition`/`BodyMetricEntry` seeded with Weight/Height/Body Fat %, user can add custom metrics), Progress screen (consistency %, trend), Goal linkage via direct `ResultMeasure` fields (`linkedNutritionMetricID`, `linkedBodyMetricDefinitionID`).

**Explicitly future:** barcode scanning, AI photo recognition, restaurant/recipe integration, full-day templates (Training Day bundling multiple meals) — the brief calls this out but it's a natural v1.1 once single-meal templates exist.

## 8. Open Implementation Notes (non-blocking, for the build phase)

1. **`ResultMeasure` sibling-linkage fields** — `linkedNutritionMetricID`/`linkedBodyMetricDefinitionID` are additive optional fields alongside the existing `linkedMeasurementDefinitionID`, consistent with the project's additive-first convention; `GoalProgressEngine` gains two new read paths (Nutrition totals, BodyMetricEntry latest/trend) alongside its existing MeasurementEntry path.
2. **Denormalized `MealEntry.totals` cache** — proposed for dashboard performance; recompute-on-read vs. cache-at-save is a small implementation-time call, doesn't affect the model shape above.
3. **Seeding `BodyMetricDefinition`** — Weight/Height/Body Fat % should be seeded per-Profile on first Nutrition module access (`isSystemDefault = true`), not hardcoded into UI, so the module stays consistent with the project's "no hardcoded per-domain logic" convention.

## 9. Mock Screens

Visual review artifact (layout/flow only, not a pixel-accurate component spec): https://claude.ai/code/artifact/b2da11bc-dcf7-42cb-a8a9-e4ceeb736bdf

Seven iPhone-frame comps (revised after review — refinements below):

1. **Dashboard** — **protein is now the primary hero ring** (calories moved to a secondary line under the ring and a plain bar in the macro list, no longer the hero metric); compact macro bars for calories/carbs/fat/water; meal checklist reusing the existing simple-completion pattern. FAB opens the Quick Action sheet (Screen 02), not meal logging directly.
2. **Quick Actions** *(new)* — bottom-sheet with three fastest actions: **+ Log Meal**, **+ Water** (one tap, default amount), **+ Weight** (minimal numeric entry) — a single entry point instead of forcing navigation into three separate screens.
3. **Meal Logging** — segmented control for the three intake paths (Templates / Manual / Quick macros), template-first; template cards show computed macros inline. **New "Recent Meals" section** — a lower-commitment alternative to Templates for one-off repeats that don't warrant naming/saving. "Logged so far" list opens Add/Edit Meal (Screen 04) on tap.
4. **Add/Edit Meal** *(new)* — one shared screen for adding foods to a fresh meal or editing an existing `MealEntry` in place per §4a's edit model. Per-food quantity steppers; **totals recompute live** (never hand-entered, matches `MealEntry.totals` as a derived cache); **"Save as Template"** bridges directly into Screen 05.
5. **Meal Templates** — usage metadata (times used, last used) retained; **new favorite/relevance concept** — a separate ★/☆ toggle pins favorited templates into their own section above the rest, distinct from usage-count sorting. Full CRUD behind swipe actions.
6. **Body Tracking** — **weight remains the primary hero** with trend strip; Body Fat %/Height stay as secondary, lower-cadence rows below; "add custom metric" row surfaces the data-driven `BodyMetricDefinition` model. Kept on its own screen, separate from meal logging, per decision #4.
7. **Progress** — four single-number stat tiles to avoid the "meaningless score" trap; kept habit/trend framing throughout. **"Linked Goal" renamed to "Your Goal"** and reworded to plain habit language ("4 of 5 days this week") — no Result Measure/linkage terminology surfaced in the UI, even though §5's `linkedNutritionMetricID` connection is what powers it underneath.

Colors/spacing in the mockup are placeholders to get pixels on screen — the build should resolve them through `ColorToken`, `LifeOSSpacing`/`LifeOSRadius`, and `SignatureProgressRing` from `DesignSystem.swift` rather than the ad hoc values shown there.
