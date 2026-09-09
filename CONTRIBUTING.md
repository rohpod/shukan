# Contributing to shukan

This document defines how we branch, commit, and merge.

## Branching model

We use a simplified trunk-based model. Three branch types:

- **`main`** — always in a working state. Protected: no direct pushes, only merges via
  reviewed pull request. This is what we'd demo at any point.
- **`dev`** — integration branch. All feature branches merge here first. May be briefly
  broken; that's fine, it's not `main`.
- **`feature/<short-description>`** — one branch per task/feature. Branched off `dev`.
  Examples: `feature/reminder-crud`, `feature/local-notifications`, `feature/auth-login`.

### Branch prefixes

Use the prefix that matches the *type* of work, same categories as commit types below,
so a branch name already tells you what kind of change to expect.

| Prefix       | Use for                                                          | Example                              |
|--------------|-------------------------------------------------------------------|---------------------------------------|
| `feature/`   | A new feature                                                     | `feature/reminder-crud`               |
| `fix/`       | A bug fix                                                         | `fix/notification-timezone-offset`    |
| `chore/`     | Tooling, dependencies, config, build scripts — no source logic   | `chore/setup-lint`                    |
| `refactor/`  | Restructuring code without changing behaviour                    | `refactor/reminders-repository`       |
| `docs/`      | Documentation only                                                | `docs/update-firebase-setup`          |
| `style/`     | Formatting only, no logic change                                 | `style/format-lib-dir`                |
| `test/`      | Adding or fixing tests                                            | `test/reminder-crud-unit-tests`       |
| `hotfix/`    | Urgent fix branched directly off `main` (bypasses `dev`)         | `hotfix/crash-on-launch`              |

Note: `hotfix/` is the one exception to "always branch off `dev`" — only use it for
something broken in production/`main` that can't wait for the normal `dev` → `main`
cycle. Merge a hotfix into both `main` and `dev` once resolved, so `dev` doesn't
regress the fix on its next merge into `main`.

### Workflow

1. Pull latest `dev` before starting anything new:
   ```bash
   git checkout dev
   git pull origin dev
   ```
2. Branch off `dev`:
   ```bash
   git checkout -b feature/reminder-crud
   ```
3. Commit small, working increments (see commit style below). Don't let a branch live
   more than 2–3 days without merging — longer-lived branches mean bigger, harder conflicts.
4. Push and open a pull request into `dev`. **Never merge your own PR without review**.
5. Once `dev` is stable and a meaningful chunk of work is done (weekly, or at a milestone),
   open a PR from `dev` into `main`.

### Merge strategy

- Use **squash merge** for feature branches into `dev` — keeps `dev` history readable as
  one commit per feature/task, even if you made 15 messy WIP commits on your branch.
- Use a regular **merge commit** for `dev` into `main`, so `main`'s history shows each
  integration point clearly.

## Commit messages — Conventional Commits

Format:

```
<type>: <short summary, imperative mood, no full stop>

<longer body — the "why", not the "what".>
```

**Types:**

| Type       | Use for                                                        |
|------------|-----------------------------------------------------------------|
| `feat`     | A new feature                                                   |
| `fix`      | A bug fix                                                        |
| `chore`    | Tooling, dependencies, config, build scripts — no source logic  |
| `refactor` | Code change that neither fixes a bug nor adds a feature         |
| `docs`     | Documentation only                                               |
| `style`    | Formatting only (no logic change) — e.g. `dart format` output   |
| `test`     | Adding or fixing tests                                           |

**Scope** (optional, in parentheses): the area affected, e.g. `feat(reminders):`, `fix(auth):`, `chore(ci):`.

**Examples:**

```
feat(reminders): add create and edit reminder screen

fix(notifications): correct timezone offset on scheduled reminders

chore: add flutter_lints and configure analysis_options.yaml

docs: add Firebase setup instructions to README
```

**Rules:**
- Imperative mood ("add", not "added" or "adds") — matches Git's own convention for
  auto-generated commits (merges, reverts).
- Keep the summary line short.
- One logical change per commit. Don't bundle a feature and an unrelated formatting pass.
- If a commit is a work-in-progress you need to push (e.g. switching machines), prefix
  with `wip:` — but squash these away before merging into `dev`.

## Pull requests

- **Title**: same convention as commit messages (e.g. `feat(reminders): reminder CRUD and Firestore sync`).
- **Description must include**:
  - What changed and why (1–3 sentences).
  - How to test it manually (steps).
  - Screenshots/screen recording if it touches UI.
  - Any known limitations or follow-up work (link an issue if applicable).
- **Before opening**: run `flutter analyze` and `dart format .` locally — don't make the
  reviewer flag formatting issues.
- **Review**: at least one of the other two contributors approves before merge. Reviewer
  should actually run the branch locally if the change touches core logic (not just UI).
- **Size**: keep PRs scoped to one feature slice. If a PR is touching more than ~400 lines
  across many unrelated files, it's probably two PRs.

## Code style

- Run `dart format .` before every commit.
- Run `flutter analyze` and resolve warnings before opening a PR.
- Follow the lint rules in `analysis_options.yaml` (uses `flutter_lints`).

## Secrets and config

- **Never commit** `google-services.json`, `GoogleService-Info.plist`, API keys, or any
  `firebase_options.dart` containing real project credentials. These must be in
  `.gitignore`. Share them via a private channel (not GitHub) among the team.
- If a secret is committed by accident: rotate/regenerate it immediately, don't just
  delete it in a follow-up commit (it stays in git history).

## Issue tracking

- Use GitHub Issues for tasks, linked to the GitHub Projects board.
- Reference issues in commits/PRs where relevant: `feat(reminders): add CRUD (#12)`.
