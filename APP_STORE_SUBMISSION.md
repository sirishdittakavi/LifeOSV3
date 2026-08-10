# LifeOS V1 — App Store Submission Record

Use this file as the single checklist for build 1. Do not submit until every checkbox is complete.

## Product identity

- App name: `LifeOS`
- Platform: iOS / iPhone
- Bundle ID: `com.sirishdittakavi.lifeos`
- Version: `1.0`
- Build: `1`
- Minimum iOS: `17.0`
- Primary category: Health & Fitness
- Suggested secondary category: Productivity
- Do not select the Kids Category for V1.

## Public URLs

- Privacy: `https://sirishdittakavi.github.io/LifeOS/privacy.html`
- Support: `https://sirishdittakavi.github.io/LifeOS/support.html`

After pushing `docs/`, enable GitHub Pages for the repository using the `main` branch and `/docs` folder. Open both URLs in a private browser window before entering them in App Store Connect.

## Suggested listing

### Subtitle

Plans, tasks and real progress

### Promotional text

Turn the areas that matter into a clear daily plan, record what happened and review honest progress over time.

### Description

LifeOS brings plans, goals, scheduled tasks and real-world progress together in one local-first iPhone app.

Use Today to see what is planned, complete or skip tasks, and record unplanned work. Organise recurring tasks inside Plans, review daily, weekly and monthly activity, and keep goal outcomes separate from effort.

LifeOS also includes manual nutrition logging and weekly meal planning, body-weight trends, sport training records, optional parent-managed profiles and portable JSON backup and restore.

Your working data stays on your iPhone in V1. No LifeOS account, advertising or analytics SDK is required.

LifeOS is not a medical device and does not provide medical diagnosis or treatment advice.

### Keywords

planner,tasks,goals,habits,progress,nutrition,fitness,schedule,family,training

## App Privacy answers for V1

Verify the final binary before answering. For the current V1 code:

- Tracking: No
- Data collected by the developer: No
- Advertising SDKs: None
- Analytics SDKs: None
- LifeOS account: None
- HealthKit: Not used
- Camera: Not requested
- Photos: Apple system photo picker is used only when the user selects an optional profile photo
- Notifications: Local reminders, requested in context

User-directed JSON export is not an upload to LifeOS. If any off-device service is added, reassess every privacy answer before submission.

## Screenshots

Capture clean, representative data rather than private family data:

1. Today with Plans above a scrollable task list.
2. Task detail with editable schedule and duration.
3. Progress with Day/Week/Month chart and Plan breakdown.
4. Plan detail with tasks and history.
5. Nutrition daily summary and weekly planned-versus-actual view.

Screenshots must match the submitted build and must not display CoachMePlus, Apple Screen Time or other third-party branding.

## App Review notes

LifeOS V1 is a local-first planning and progress app and does not require a login.

On first launch, complete the three-step onboarding to create editable Plans, Goals and scheduled Tasks. The Today tab renders persisted scheduled occurrences. Tap a Task to view and edit its details. The Progress tab provides Day, Week and Month reporting. Manage Profiles, Backup & Restore, Privacy and Support are available from the profile menu.

Optional child profiles are parent-managed on the same iPhone. V1 does not provide remote child monitoring, child accounts or cross-device sharing.

Nutrition, weight and sport data are manually entered. LifeOS is not a medical device and does not provide diagnosis or treatment advice. Barcode scanning and nutrition-label camera capture are not included in V1.

## Final verification

- [ ] Apple Developer agreements are accepted.
- [ ] Bundle ID is registered and matches Xcode.
- [ ] Automatic signing uses the intended paid Developer team.
- [ ] Privacy and Support URLs work without signing in.
- [ ] App icon is final and contains no alpha channel.
- [ ] Privacy manifest is included in the archived app.
- [ ] Archive succeeds using the Release configuration.
- [ ] Uploaded build processes successfully in App Store Connect.
- [ ] Fresh-install TestFlight scenario passes on a physical iPhone.
- [ ] Upgrade TestFlight scenario preserves existing data.
- [ ] Notification allow/deny paths work.
- [ ] Backup export and restore work with realistic data.
- [ ] Light mode, dark mode, Dynamic Type and VoiceOver smoke checks pass.
- [ ] App Privacy answers match the uploaded binary.
- [ ] Screenshots and description match the uploaded build.
