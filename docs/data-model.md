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
security). Firestore security rules (draft, refine once auth flow is built):

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

Whoever builds Auth (see grouped work plan) should add these rules in Firebase Console
→ Firestore → Rules early — don't leave the database in open "test mode" once real
auth exists, even for local dev among the three of you.

---
