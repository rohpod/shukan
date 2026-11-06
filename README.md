# shukan (習慣)

A cross-platform habit-tracking app, built with Flutter — where the discipline
philosophies of anime characters shape how you build and stick to your habits.

Currently in **foundation phase**: building a robust reminders application first, before
layering habit-tracking and anime-philosophy theming on top.

## Status

🚧 Phase 1 (reminders) is code-complete and has passed its manual browser checks, but
isn't live yet. Implemented:
authentication and password reset, tasks and lists (CRUD, soft delete with a 30-day
Recently Deleted), tags, search, smart views, subtasks, repeating tasks (daily, weekly,
monthly and custom schedules), due-date reminders, offline-safe saves, account settings,
and JSON/Markdown export. Habit tracking (Phase 2) comes next — see [Roadmap](#roadmap).

Still to do before Phase 1 is finished:

- Deploy hosting, and review the report-only Content Security Policy on a live run.
- Merge `dev` into `main`.

**Reminders are tab-only.** They fire through the browser while a shukan tab is open,
including catching up on ones missed while it was closed. Nothing is delivered when every
tab is closed; that needs push notifications (see Backlog).

## Tech stack

- **Framework:** Flutter (Dart), Web-first (Android/iOS to follow)
- **Backend:** Firebase Auth, Cloud Firestore
- **Notifications:** `flutter_local_notifications` (browser notifications on web, shown
  by an in-app scheduler while a tab is open)
- **State management:** Riverpod

## Roadmap

1. **Phase 1 — Reminders foundation:** CRUD for reminders, browser reminders, Firestore sync, auth.
2. **Phase 2 — Habit tracking:** recurring habits, daily check-ins, streaks, history.
3. **Phase 3 — Anime philosophy theming:** philosophy selection, themed framing of habits/reminders.
4. **Phase 4 — Polish:** UI/UX pass, additional philosophies, settings, notifications refinement.

## Getting started

### Prerequisites

- Flutter SDK (stable channel) — verify with `flutter doctor`
- A Google account added as a collaborator on the `shukan-loop` Firebase project
  (ask a maintainer)
- Node.js (for the Firebase CLI and the rules tests)
- Java (for the Firestore emulator, if you'll be running the rules tests)

### Setup

```bash
git clone https://github.com/rohpod/shukan.git
cd shukan
flutter pub get
```

You'll also need to generate your own local Firebase configuration — see
[docs/firebase-setup.md](docs/firebase-setup.md). This step is required before
`flutter run` will build; `lib/firebase_options.dart` is intentionally gitignored
and isn't included in the repo.

```bash
flutter run -d chrome
```

## Tests

```bash
flutter analyze
flutter test
TZ=America/New_York flutter test test/features/tasks/domain   # date logic under DST
```

Only run `test/features/tasks/domain` under that timezone. The full suite has 11 known
failures there, because some notification test fixtures use UTC dates.

`fake_cloud_firestore` doesn't enforce `firestore.rules`, so rules have their own
emulator tests:

```bash
npm --prefix test_rules ci
firebase emulators:exec --only firestore --project demo-shukan "npm --prefix test_rules test"
```

## Deploying

Nothing deploys automatically. With Editor access to `shukan-loop`:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project shukan-loop
flutter build web
firebase deploy --only hosting --project shukan-loop
```

Hosting sends the Content Security Policy as `Content-Security-Policy-Report-Only`.
Review the browser console for violations on a live run before switching it to an
enforced `Content-Security-Policy` in `firebase.json`. See
[docs/firebase-setup.md](docs/firebase-setup.md) for details.

## Backlog (not in Phase 1)

- Closed-tab reminders (FCM web push)
- Snooze, and email verification
- Native notifications: `requestPermissions()` is never called, there's no rescheduling
  at startup, and deleting a list or signing out doesn't cancel notifications. Fix when
  `android/` and `ios/` are added.
- Timezone travel: `dueDate` is stored as local midnight, so changing timezone can
  shift the date
- Firestore read cost: about five overlapping task listeners on home, and
  `streamRecentlyDeletedTasks` reads every task. Move to one shared listener before growth.
- Clearing the local cache on sign-out (shared computers), App Check, a crash reporting
  service, reminders for recurring tasks left uncompleted
- Splitting `task_list_screen.dart`, which is over 1,700 lines
- Catch-up across devices: the missed-reminder summary runs on the first cached task
  list, so a task that only arrives from the server afterwards isn't counted
- Test and tooling cleanup: the UTC fixtures above, a reporting address for the Content
  Security Policy, and the `npm audit` findings in the `test_rules/` dev dependencies

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branching model, commit conventions, and PR process.

## License

[MIT](LICENSE)

## Acknowledgements

Development of this application was supported by Antigravity.
