# shukan (習慣)

A cross-platform reminders and habit-tracking app, built with Flutter — where the discipline
philosophies of anime characters shape how you build and stick to your habits.

Currently in **foundation phase**: building a robust reminders application first, before
layering habit-tracking and anime-philosophy theming on top.

## Status

🚧 Early development. Not yet functional.

## Tech stack

- **Framework:** Flutter (Dart)
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
- Xcode (for iOS builds, macOS only)
- Android Studio / Android SDK (for Android builds)
- A Firebase project (see `docs/firebase-setup.md` — to be added)

### Setup

```bash
git clone https://github.com/<org>/shukan.git
cd shukan
flutter pub get
flutter run
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branching model, commit conventions, and PR process.

## License

[MIT](LICENSE)
