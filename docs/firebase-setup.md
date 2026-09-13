# Firebase setup

`lib/firebase_options.dart` and `.firebaserc` are intentionally excluded from
git (see `CONTRIBUTING.md` — Secrets and config). Every contributor generates
their own copy locally. This takes about five minutes.

## 1. Get added to the Firebase project

Ask a maintainer to add your Google account as a collaborator on the
`shukan-loop` Firebase project (Firebase Console → Project Settings → Users
and permissions → Add member → Editor role). You need this before step 3 will
work.

## 2. Install the tools

You'll need the Firebase CLI and the FlutterFire CLI.

```bash
# Firebase CLI (skip if you already have it)
npm install -g firebase-tools

# FlutterFire CLI
dart pub global activate flutterfire_cli
```

Log in to Firebase with the Google account you were added with:

```bash
firebase login
```

## 3. Generate your local config

From the repo root:

```bash
flutterfire configure --project=shukan-loop
```

When prompted for platforms, select **web** — this project is web-only for
now (see README for why). This command writes `lib/firebase_options.dart` for
you. It's gitignored, so it stays local to your machine — don't try to commit
it.

## 4. Set your active Firebase project (for CLI commands)

`.firebaserc` is also gitignored, so the Firebase CLI won't know which project
you mean by default. Either:

```bash
firebase use --add
# then select shukan-loop when prompted
```

or just pass `--project shukan-loop` on any Firebase CLI command you run
(e.g. `firebase deploy --only firestore:rules --project shukan-loop`).

## 5. Verify

```bash
flutter pub get
flutter run -d chrome
```

You should be able to sign up, log in, and see the home screen. If
`flutter run` fails with something like `Target of URI doesn't exist:
'firebase_options.dart'`, step 3 didn't complete — re-run
`flutterfire configure`.

## Deploying rules or indexes

Firestore security rules (`firestore.rules`) and composite indexes
(`firestore.indexes.json`) are version-controlled in this repo. If you change
either, deploy with:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project shukan-loop
```

Anyone with Editor access can do this — no special setup beyond what's above.
