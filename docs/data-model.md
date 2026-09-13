# shukan — Firestore Data Model

Auth is required from day one. Every collection below is scoped to `uid`, and no
task/list/tag exists without an authenticated user owning it.

**Adding new fields later is free. Renaming/retyping existing fields once real data
exists is costly.** Don't rename anything below without a team discussion.

---

## Collections overview

```
users/{uid}
lists/{listId}
tasks/{taskId}
tags/{tagId}
```
---

## `users/{uid}`

```
{
  uid: string,
  email: string,
  displayName: string,
  createdAt: timestamp,
  defaultListId: string
}
```
---

## `lists/{listId}`

```
{
  listId: string,
  uid: string,
  name: string,
  createdAt: timestamp,
  isDefault: boolean
}
```
---

## `tags/{tagId}`

```
{
  tagId: string,        // document ID, auto-generated
  uid: string,          // owner — tags are per-user, not global across all users
  name: string,          // e.g. "college", "urgent"
  createdAt: timestamp
}
```

Not yet implemented — schema is defined here so #3/#11 can build against it directly.

---

## `tasks/{taskId}`

```
{
  taskId: string,
  uid: string,
  listId: string,

  title: string,
  notes: string,
  url: string,

  priority: string,           // "none" | "low" | "medium" | "high"
  tagIds: array<string>,      // references tags/{tagId}
  dueDate: timestamp | null,
  dueTime: string | null,     // "HH:mm"
  earlyReminderMinutes: number,
  repeatRule: string,         // "none" | "daily" | "weekly" | "monthly" | "custom"
  repeatCustomConfig: map | null,   // stub — shape defined when custom repeat is built

  order: number,

  subtasks: array<{
    id: string,
    title: string,
    completed: boolean
  }>,

  createdAt: timestamp,
  completedAt: timestamp | null,
  deletedAt: timestamp | null
}
```
---

## Auth requirement — what this means practically

Every Firestore query in every feature must filter by `uid == currentUser.uid` (via
Firestore security rules, not just client-side filtering — client-side alone is not
security).

**Live rules are in `firestore.rules` at the repo root — that file is the source of
truth, not the draft below.** It's kept in version control and deployed via
`firebase deploy --only firestore:rules` (see `docs/firebase-setup.md`). The draft
below is preserved for historical context (this is what was originally planned
before Auth/List CRUD were built) — it has since been superseded, specifically:
`lists/{listId}` now splits `update` and `delete` permissions, with `delete` requiring
`resource.data.isDefault == false` so the default Inbox list can't be removed.

<details>
<summary>Original draft rules (superseded — see firestore.rules for current state)</summary>

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /lists/{listId} {
      allow read, write: if request.auth != null && request.auth.uid == resource.data.uid;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.uid;
    }
    match /tasks/{taskId} {
      allow read, write: if request.auth != null && request.auth.uid == resource.data.uid;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.uid;
    }
    match /tags/{tagId} {
      allow read, write: if request.auth != null && request.auth.uid == resource.data.uid;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.uid;
    }
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

</details>

## Indexes

Composite indexes required by current queries are tracked in
`firestore.indexes.json` at the repo root (also the source of truth — deploy via
`firebase deploy --only firestore:indexes`). Currently:

- `tasks`: `uid` + `listId` + `deletedAt` + `createdAt` (ascending) — supports
  streaming a list's active tasks ordered by creation time.
- `lists`: `uid` + `createdAt` (ascending) — supports streaming a user's lists
  ordered by creation time.

If you add a new compound query, Firestore will tell you the exact index it
needs the first time you run it (error message includes a console link). Add
the resulting index definition to `firestore.indexes.json` rather than only
creating it via the console, so it's captured for the whole team.

---
