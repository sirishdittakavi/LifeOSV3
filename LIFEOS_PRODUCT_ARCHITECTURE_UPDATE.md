# LifeOS Product Architecture Update

## Purpose

LifeOS is evolving from a simple task tracking application into a **generic personal improvement platform**.

The core purpose:

> Help people convert goals into activities, schedule them, execute them, measure progress, and continuously improve.

LifeOS is NOT a fitness app, coding app, sports app, or productivity app.

It is a universal improvement system that can support any area of life:

- Sport
- Learning
- Career
- Health
- Creative skills
- Family
- Personal projects
- Any user-defined improvement area

---

# Core LifeOS Flow

The fundamental model:

Person
  |
  |
Area
  |
  |
Goal
  |
  |
Activity Template
  |
  |
Schedule
  |
  |
Activity Session
  |
  |
Measurements
  |
  |
Progress
  |
  |
Insights

---

# 1. Person-Centric Design

LifeOS should not assume one account represents only one person.

An account can manage one or more person profiles.

Example:

Account
 |
 +----------------+
 |                |
Person A        Person B
Adult           Child

Each person has their own:

- Goals
- Activities
- Schedules
- Sessions
- Measurements
- Progress

---

# 2. Relationships (Future Capability)

Do not hardcode roles such as:

- Parent
- Coach
- Teacher
- Athlete
- Student

These are examples of relationships.

The core concept is:

Person A
|
|
Relationship
|
|
Person B

Examples:

Parent relationship
Coach relationship
Mentor relationship
Teacher relationship

Relationships control:

- View permissions
- Edit permissions
- Activity management
- Notifications
- Progress visibility

---

# 3. Goals

Everything starts with a goal.

Examples:

Goal:
Improve Baseball Skills

Goal:
Learn Guitar

Goal:
Become Better Software Engineer

Goal:
Improve Health

Goals define:

- What the person wants to improve
- Target outcome
- Timeline
- Priority

---

# 4. Generic Activity Model

LifeOS should NOT create separate models for every domain.

Avoid:

BaseballActivity
SwimmingActivity
MusicActivity
CodingActivity

Instead:

Activity Template

Examples:

Baseball Practice
Swimming Training
Guitar Practice
Programming Study
Reading
Meditation

The same activity engine supports all domains.

---

# 5. Dynamic Measurements

IMPORTANT:

LifeOS must not hardcode activity-specific fields.

The system should allow users to decide:

> "What do I want to measure to know I am improving?"

---

## Example: Baseball Fielding

Activity:

Fielding Practice

Basic tracking:

Completed
Duration

User can add:

Ground Balls
Type: Count
Fly Balls
Type: Count
Catches
Type: Count
Reaction Time
Type: Seconds
Throw Accuracy
Type: Percentage

---

## Example: Swimming

Swimming Training

Measurements:

Distance
Duration
Laps
Stroke Type
Pace

---

## Example: Music

Guitar Practice

Measurements:

Practice Time
Songs Completed
Chords Learned
Difficulty Level

---

## Example: Software Learning

Programming Practice

Measurements:

Study Duration
Problems Solved
Topics Completed
Confidence Rating

---

# Measurement Rules

Measurements should be:

- Optional
- User configurable
- Editable later
- Addable without database schema changes

Users can:

- Add measurements
- Remove measurements
- Change targets
- Add notes

---

# 6. Progressive Tracking Model

LifeOS must support different levels of users.

## Level 1 - Casual User

Simple tracking.

Example:

Reading
Completed
Duration:
30 minutes

Only requires:

- Completion
- Duration

---

## Level 2 - Serious User

User wants improvement tracking.

Example:

Baseball Practice
Duration:
60 minutes
Ground Balls:
100
Catches:
50

---

## Level 3 - Professional User

Structured programs.

Example:

8 Week Baseball Improvement Program
Targets:
300 Ground Balls
90% Throw Accuracy
Improve Reaction Time

---

Users should start simple and add complexity when needed.

---

# 7. Planned vs Actual Separation

LifeOS must separate:

## Planned Activity

"What I intended to do"

Example:

Swimming Practice
Saturday
45 minutes

---

## Activity Session

"What actually happened"

Example:

Completed:
60 minutes
2km distance
40 laps

---

This allows LifeOS to understand:

- Planned behaviour
- Actual behaviour
- Completion trends
- Improvement patterns

---

# 8. Dashboard Philosophy

Inspired by WHOOP simplicity.

The goal:

> User understands their day within 5 seconds.

The dashboard should answer:

1. What should I do today?
2. What did I complete?
3. Am I progressing?

---

Example:

TODAY
Progress
78%
NEXT
Baseball Practice
45 minutes
[ Start ]
COMPLETED
✓ Reading
✓ Exercise
✓ Learning

---

# 9. Calendar Philosophy

Calendar is not the main product.

Calendar answers:

> "What activities are planned?"

Keep it simple.

Views:

Today
Week

Avoid becoming a complex calendar application.

---

# 10. Architecture Layers

Maintain clean separation:

SwiftUI View
  |
ViewModel
  |
Use Cases
  |
Repository Interface
  |
Data Source

Current:

SwiftData

Future:

Supabase / PostgreSQL

Possible future:

Backend APIs

---

# 11. AI Direction

AI should not be the foundation.

First:

User Data
|
Calculation Engine
|
Progress
|
Insights

AI comes later:

AI Coach

AI responsibilities:

- Suggest activities
- Explain patterns
- Recommend improvements
- Help planning

AI should not replace core calculations.

---

# 12. Future Notification Engine

Notifications should be generic.

Flow:

Scheduled Activity
    |
Expected Completion
    |
Actual Completion
    |
Rule Engine
    |
Notification

Examples:

Activity missed
Goal progress dropping
Consistency improving
Milestone achieved

---

# 13. Core Product Principle

LifeOS should be:

Simple for beginners
Powerful for advanced users
Flexible for professionals

The system should support:

Casual user:
Track completion
Serious user:
Track measurements
Professional user:
Create structured programs

---

# Required Documentation Updates

Update:

Architecture.md
REFACTORING.md

Include:

- Person/Profile concept
- Relationship model
- Generic Activity model
- Dynamic Measurement model
- Planned vs Actual separation
- Progressive tracking approach
- Simple dashboard principles

---

# Implementation Rule

Do not implement code changes based on this document yet.

First:

1. Update architecture documents
2. Review existing models
3. Identify migration risks
4. Agree implementation phases
5. Then refactor code

The goal is to avoid building a narrow tracker and instead create a scalable personal improvement platform.