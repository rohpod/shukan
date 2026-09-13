# shukan (習慣)

A cross-platform habit-tracking app, built with Flutter — where the discipline
philosophies of anime characters shape how you build and stick to your habits.

Currently in **foundation phase**: building a robust reminders application first, before
layering habit-tracking and anime-philosophy theming on top.

## Status

🚧 Early development. Authentication, Task CRUD, and List CRUD are implemented. 
Not yet feature-complete — see [Roadmap](#roadmap).

## Tech stack

- **Framework:** Flutter (Dart), Web-first (Android/iOS to follow)
- **Backend:** Firebase Auth, Cloud Firestore
- **Notifications:** `flutter_local_notifications` (on-device scheduling)
- **State management:** Riverpod

## Roadmap

1. **Phase 1 — Reminders foundation:** CRUD for reminders, local notification scheduling, Firestore sync, auth.
2. **Phase 2 — Habit tracking:** recurring habits, daily check-ins, streaks, history.
3. **Phase 3 — Anime philosophy theming:** philosophy selection, themed framing of habits/reminders.
4. **Phase 4 — Polish:** UI/UX pass, additional philosophies, settings, notifications refinement.

## Getting started

### Prerequisites

- Flutter SDK (stable channel) — verify with `flutter doctor`
- A Google account added as a collaborator on the `shukan-loop` Firebase project
  (ask a maintainer)
- Node.js (for the Firebase CLI, if you'll be deploying rules/indexes)

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branching model, commit conventions, and PR process.

## License

[MIT](LICENSE)

## Acknowledgements

Development of this application was supported by Antigravity.
