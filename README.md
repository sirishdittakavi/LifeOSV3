# LifeOS — v1.4 Prototype (Calendar/Timeline rebuild)

This replaces the earlier Momentum-ring prototype with the calendar-centric
design from `DESIGN.md` v1.4: Activities generate Calendar Items on a daily
timeline, Planned and Actual are tracked separately, and Section 10a adds a
dedicated Daily Progress view (target vs. actual) alongside completion status.

## What's included

```
LifeOS/
  LifeOSApp.swift              — entry point, SwiftData container, seeds parent+child profiles
  Models/
    Models.swift                — Profile, Category, Activity (+schedule rule), CalendarItem, Session
    SeedData.swift               — parent (Sirish) + child (Junior/athlete) starter activities
  Engine/
    PlanningService.swift        — generates missing Calendar Items from schedule rules (pure, testable)
    ProgressEngine.swift         — completion summary (Section 9) + daily target-vs-actual (Section 10a)
  Views/
    RootTabView.swift            — Today / Progress tabs, shared profile selection
    TodayTimelineView.swift      — Screen: Today's chronological plan (Section 12 mockup)
    RecordActualView.swift       — Fast "Done" flow: record actual value, mark item Done
    AddActivityView.swift        — Create a recurring Activity (once/daily/weekdays)
    AddWhatHappenedView.swift    — Section 11: unplanned/manual entry, "add once" or "save as reusable"
    DailyProgressView.swift      — Section 10a: today's target-vs-actual + 7-day trend
    ColorToken.swift             — maps stored color strings to SwiftUI Color
```

## How to run it

Same pattern as before — Xcode → New Project → iOS App → SwiftUI + SwiftData
→ delete generated `ContentView.swift`/`Item.swift` → replace `LifeOSApp.swift`
→ drag in `Models/`, `Engine/`, `Views/` (check "Copy items if needed" and the
target) → `Cmd+R` on any simulator. Fully offline, no camera/network needed.

## Try this once it's running

1. Launch — you land on **Today** as Sirish (parent), with today's schedule
   already generated from the seeded activities: Gym, Office Work, Family
   Dinner, Java Practice.
2. Tap the profile menu (top-left) → switch to **Junior** — a completely
   separate calendar: School, Homework, Hitting Practice, Reading.
3. On any item, tap **Start** → status becomes "In Progress." Tap **Finish**
   → for a target-tracked activity (e.g. Hitting Practice), enter the actual
   number (swings) → **Save**. The item turns "Done," and that number now
   feeds the Progress tab.
4. Go to **Progress** tab — see today's target vs. actual bars, and a 7-day
   trend per tracked activity (builds up as you log more days).
5. Back on Today, tap **+** → **Create Activity** to add your own recurring
   item (e.g. a custom weekday-only routine).
6. Tap **Add What Happened** for something unplanned — logs a one-time entry
   immediately as Done, with the option to make it recurring going forward.

## Deliberately not built yet (see DESIGN.md Section 0/15/16)

Dedicated timer screen (Start/Finish here is instant, not a running clock),
Repository protocol layer, JSON export/auto-snapshot, local notifications,
multiple tracking fields per activity, Goal entity, Face ID/PIN, cloud sync.
Priority order for what's next is in DESIGN.md Section 16.
