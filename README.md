# LifeOS

LifeOS is a local-first iPhone app for turning improvement areas into scheduled actions, recording what happened, and showing whether each area is on track today, this week, and this month. The current product specification is `DESIGN.md` Version 1.

## Current capabilities

- Dashboard confidence by improvement category and period
- Today timeline and interactive weekly calendar
- Editable category hierarchy, relationships, targets and reminders
- Flexible task repetition by weekday, count and exact minute interval
- Food capture by barcode, nutrition-label photo or manual entry
- Weight tracking in kilograms or pounds
- Generic sport training and workload tracking using each user's editable Sport Area
- Multiple separate adult, child or individual profiles
- Optional profile photos and parent-managed/self-managed intent
- Reusable templates plus full JSON backup and restore

## Profiles

A fresh install starts with one neutral **My Profile** owner. Child and additional adult profiles are optional and can be added from **Manage Profiles**. Each profile has separate schedules, categories, progress, food, weight and sport records. Profiles may be renamed, photographed, hidden and restored without deleting their history.

Parent-managed profiles work locally on the parent's device today. Self-managed access from a child's separate phone requires the future Family Sync account and permission service described in `DESIGN.md`; it is not represented as active multi-device sync in this build.

## Run

Open `LifeOS.xcodeproj` in Xcode, select an iPhone simulator or trusted physical iPhone, and press **Command-R**. Physical devices require Automatic Signing, an Apple Personal Team, Developer Mode and trust for the developer profile.

The app requires iOS 17 or later and stores its working data on-device with SwiftData.

## Project layout

```text
LifeOS/
  LifeOSApp.swift
  Models/       SwiftData domain models and first-run seed data
  Engine/       planning, progress, reminders, capture and backup services
  Views/        dashboard, calendar, categories, profiles and trackers
DESIGN.md       living product and engineering specification
project.yml     XcodeGen project definition
```

## Deferred platform work

Secure accounts, Family Sync, child invitations/permissions, server-validated paid household entitlements and organisation/coach workflows remain later milestones. Local profiles and backups must remain usable even if a future subscription expires.
