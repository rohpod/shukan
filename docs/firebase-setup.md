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
now (Android and iOS come later). This command writes `lib/firebase_options.dart` for
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

## Testing rules locally

`fake_cloud_firestore` doesn't enforce `firestore.rules`, so every rules change
needs an emulator test in `test_rules/rules.test.mjs`. From the repo root:

```bash
npm --prefix test_rules ci
firebase emulators:exec --only firestore --project demo-shukan "npm --prefix test_rules test"
```

The emulator needs Java. `demo-shukan` is a demo project, so nothing touches the real
backend.

## Hosting

`firebase.json` has a `hosting` block that serves `build/web` with a single-page rewrite,
`no-cache` on `js`/`json`/`html` (Flutter's `main.dart.js` isn't content-hashed), a week of
caching for `canvaskit/**`, and security headers.

Check the headers locally before deploying:

```bash
flutter build web
firebase emulators:exec --only hosting --project demo-shukan "curl -sI http://127.0.0.1:5010/"
```

Deploy with:

```bash
flutter build web
firebase deploy --only hosting --project shukan-loop
```

The Content Security Policy ships as `Content-Security-Policy-Report-Only` because an
enforced policy can break CanvasKit or Firebase and can't be proven safe without a live
run. After deploying, load the app, sign in, and use it with the browser console open.
Violations are logged there. Once there are none, rename the header to
`Content-Security-Policy` in `firebase.json` and redeploy.
