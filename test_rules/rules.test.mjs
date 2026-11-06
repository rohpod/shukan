// Runs firestore.rules against the Firestore emulator. From the repo root:
//   npm --prefix test_rules ci
//   firebase emulators:exec --only firestore --project demo-shukan "npm --prefix test_rules test"
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;
const alice = () => env.authenticatedContext('alice').firestore();
const anon = () => env.unauthenticatedContext().firestore();

const newTask = (id, overrides = {}) => ({
  taskId: id,
  uid: 'alice',
  listId: 'inbox',
  title: 'Task',
  notes: '',
  url: '',
  priority: 'none',
  tagIds: [],
  dueDate: null,
  dueTime: null,
  earlyReminderMinutes: 0,
  repeatRule: 'none',
  repeatCustomConfig: null,
  order: 0,
  subtasks: [],
  createdAt: serverTimestamp(),
  completedAt: null,
  deletedAt: null,
  ...overrides,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shukan',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8091,
    },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { uid: 'alice', defaultListId: 'inbox' });
    await setDoc(doc(db, 'lists/inbox'), { listId: 'inbox', uid: 'alice', name: 'Inbox', isDefault: true });
    await setDoc(doc(db, 'lists/work'), { listId: 'work', uid: 'alice', name: 'Work', isDefault: false });
    await setDoc(doc(db, 'lists/bobs'), { listId: 'bobs', uid: 'bob', name: 'Bob', isDefault: false });
    await setDoc(doc(db, 'tasks/t1'), { taskId: 't1', uid: 'alice', listId: 'inbox', title: 'Mine', deletedAt: null });
    await setDoc(doc(db, 'tasks/b1'), { taskId: 'b1', uid: 'bob', listId: 'bobs', title: 'Bob', deletedAt: null });
    await setDoc(doc(db, 'tags/g1'), { tagId: 'g1', uid: 'alice', name: 'home' });
  });
});

describe('reads', () => {
  test('a missing list or task reads as not found', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'lists/gone')));
    await assertSucceeds(getDoc(doc(alice(), 'tasks/gone')));
  });

  test("another user's documents stay unreadable", async () => {
    await assertFails(getDoc(doc(alice(), 'lists/bobs')));
    await assertFails(getDoc(doc(alice(), 'tasks/b1')));
  });

  test('signed-out users cannot read, even missing documents', async () => {
    await assertFails(getDoc(doc(anon(), 'lists/gone')));
    await assertFails(getDoc(doc(anon(), 'tasks/t1')));
  });

  test('queries need a uid filter', async () => {
    const tasks = collection(alice(), 'tasks');
    await assertFails(getDocs(query(tasks, where('listId', '==', 'inbox'))));
    await assertSucceeds(
      getDocs(query(tasks, where('uid', '==', 'alice'), where('listId', '==', 'inbox'))),
    );
  });
});

describe('lists', () => {
  test('sign-up batch can create the user doc and default list together', async () => {
    const db = env.authenticatedContext('carol').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/carol'), { uid: 'carol', defaultListId: 'c-inbox' });
    batch.set(doc(db, 'lists/c-inbox'), {
      listId: 'c-inbox',
      uid: 'carol',
      name: 'Inbox',
      createdAt: serverTimestamp(),
      isDefault: true,
    });
    await assertSucceeds(batch.commit());
  });

  test('a second default list is rejected', async () => {
    await assertFails(
      setDoc(doc(alice(), 'lists/l2'), { listId: 'l2', uid: 'alice', name: 'x', isDefault: true }),
    );
  });

  test('isDefault cannot be changed', async () => {
    await assertFails(updateDoc(doc(alice(), 'lists/inbox'), { isDefault: false }));
  });

  test('the default list cannot be deleted on its own', async () => {
    await assertFails(deleteDoc(doc(alice(), 'lists/inbox')));
  });

  test('the default list can be deleted with the account', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.delete(doc(db, 'users/alice'));
    batch.delete(doc(db, 'lists/inbox'));
    await assertSucceeds(batch.commit());
  });

  test('custom lists can be renamed and deleted', async () => {
    await assertSucceeds(updateDoc(doc(alice(), 'lists/work'), { name: 'Job', icon: 'work' }));
    await assertSucceeds(deleteDoc(doc(alice(), 'lists/work')));
  });

  test('list uid cannot be reassigned', async () => {
    await assertFails(updateDoc(doc(alice(), 'lists/work'), { uid: 'bob' }));
  });
});

describe('tasks', () => {
  test('a well-formed task can be created', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'tasks/t2'), newTask('t2')));
  });

  test("a task cannot point at another user's list", async () => {
    await assertFails(setDoc(doc(alice(), 'tasks/t2'), newTask('t2', { listId: 'bobs' })));
    await assertFails(updateDoc(doc(alice(), 'tasks/t1'), { listId: 'bobs' }));
  });

  test('a task can move between own lists', async () => {
    await assertSucceeds(updateDoc(doc(alice(), 'tasks/t1'), { listId: 'work' }));
  });

  test('task uid cannot be reassigned', async () => {
    await assertFails(updateDoc(doc(alice(), 'tasks/t1'), { uid: 'bob' }));
  });

  test('oversized and mistyped fields are rejected', async () => {
    const db = alice();
    await assertFails(setDoc(doc(db, 'tasks/t2'), newTask('t2', { title: 'x'.repeat(501) })));
    await assertFails(setDoc(doc(db, 'tasks/t2'), newTask('t2', { priority: 42 })));
    await assertFails(setDoc(doc(db, 'tasks/t2'), newTask('t2', { dueDate: 'nope' })));
    await assertFails(setDoc(doc(db, 'tasks/t2'), newTask('t2', { junk: true })));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { title: '' }));
  });

  test('documents without newer fields stay editable', async () => {
    await assertSucceeds(updateDoc(doc(alice(), 'tasks/t1'), { completedAt: new Date() }));
  });

  test('tasks orphaned by a deleted list can still be restored', async () => {
    const db = alice();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'tasks/t3'), {
        taskId: 't3', uid: 'alice', listId: 'gone', title: 'Old', deletedAt: new Date(),
      });
    });
    await assertSucceeds(updateDoc(doc(db, 'tasks/t3'), { deletedAt: null, listId: 'inbox' }));
  });
});

describe('custom repeat config', () => {
  let n = 0;
  const create = (config) => {
    const id = `c${n++}`;
    return setDoc(doc(alice(), `tasks/${id}`), newTask(id, { repeatRule: 'custom', repeatCustomConfig: config }));
  };

  test('valid day and week configs are accepted, and null stays allowed', async () => {
    await assertSucceeds(create({ unit: 'day', interval: 3 }));
    await assertSucceeds(create({ unit: 'week', interval: 2, weekdays: [1, 3] }));
    await assertSucceeds(create(null));
  });

  test('invalid shapes are rejected', async () => {
    await assertFails(create({}));
    await assertFails(create({ unit: 'month', interval: 1 }));
    await assertFails(create({ unit: 'day', interval: 0 }));
    await assertFails(create({ unit: 'day', interval: 366 }));
    await assertFails(create({ unit: 'day', interval: 1.5 }));
    await assertFails(create({ unit: 'day', interval: '2' }));
    await assertFails(create({ unit: 'day', interval: 2, weekdays: [1] }));
    await assertFails(create({ unit: 'week', interval: 1 }));
    await assertFails(create({ unit: 'week', interval: 1, weekdays: [] }));
    await assertFails(create({ unit: 'week', interval: 1, weekdays: [0] }));
    await assertFails(create({ unit: 'week', interval: 1, weekdays: [8] }));
    await assertFails(create({ unit: 'week', interval: 1, weekdays: [1], extra: true }));
  });

  test('updates validate the config, but an unchanged legacy doc stays editable', async () => {
    const db = alice();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'tasks/legacy'), {
        taskId: 'legacy', uid: 'alice', listId: 'inbox', title: 'Old',
        repeatRule: 'custom', repeatCustomConfig: { anything: 'goes' }, deletedAt: null,
      });
    });
    await assertSucceeds(updateDoc(doc(db, 'tasks/legacy'), { completedAt: new Date() }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { repeatCustomConfig: { unit: 'day' } }));
    await assertSucceeds(
      updateDoc(doc(db, 'tasks/t1'), {
        repeatRule: 'custom',
        repeatCustomConfig: { unit: 'week', interval: 1, weekdays: [7] },
      }),
    );
    await assertSucceeds(updateDoc(doc(db, 'tasks/t1'), { repeatRule: 'none', repeatCustomConfig: null }));
  });
});

describe('tags and users', () => {
  test('tags are owner-only and validated', async () => {
    const db = alice();
    await assertSucceeds(
      setDoc(doc(db, 'tags/g2'), { tagId: 'g2', uid: 'alice', name: 'x', createdAt: serverTimestamp() }),
    );
    await assertFails(setDoc(doc(db, 'tags/g3'), { tagId: 'g3', uid: 'bob', name: 'x' }));
    await assertFails(updateDoc(doc(db, 'tags/g1'), { name: 'x'.repeat(101) }));
    await assertFails(updateDoc(doc(db, 'tags/g1'), { uid: 'bob' }));
    await assertSucceeds(deleteDoc(doc(db, 'tags/g1')));
  });

  test('user docs are private to their owner', async () => {
    await assertFails(getDoc(doc(alice(), 'users/bob')));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { uid: 'bob' }));
    await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { displayName: 'A' }));
  });
});
