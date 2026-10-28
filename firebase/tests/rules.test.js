// Firestore security rules tests (T-14 unit 4, Q-8 B). They need the
// Firestore emulator: run them through `firebase emulators:exec` as the
// runbook shows, which sets FIRESTORE_EMULATOR_HOST.
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
  setDoc,
  setLogLevel,
  writeBatch,
} from 'firebase/firestore';

const OWNER = 'owner-uid';
const OTHER = 'other-uid';

// Shaped like ListDefinition.toJson().
function list(id, extra = {}) {
  return {
    formatVersion: 1,
    id,
    name: 'Plants',
    icon: 'eco',
    color: '#4caf50',
    schemaRevision: 2,
    fields: [{ key: 'name', type: 'text', required: true, primary: true }],
    view: { kind: 'checklist' },
    behaviors: [],
    aiAllowed: true,
    updatedAt: '2026-03-01T00:00:00.000Z',
    ...extra,
  };
}

// Shaped like the store's item document: ListItem.toJson() plus `_rev`.
function item(id, listId, extra = {}) {
  return {
    id,
    listId,
    values: { name: 'fern' },
    createdAt: '2026-03-01T00:00:00.000Z',
    updatedAt: '2026-03-01T00:00:00.000Z',
    _rev: 2,
    ...extra,
  };
}

function without(data, key) {
  const copy = { ...data };
  delete copy[key];
  return copy;
}

let env;

before(async () => {
  // Denied writes are the expected outcome; keep the SDK from logging each.
  setLogLevel('silent');
  env = await initializeTestEnvironment({
    projectId: 'tac368-hybrid-note-app',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  // Seed as an admin: one list with one item in each user's tree.
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const uid of [OWNER, OTHER]) {
      await setDoc(doc(db, `users/${uid}/lists/plants`), list('plants'));
      await setDoc(doc(db, `users/${uid}/lists/plants/items/fern`), item('fern', 'plants'));
    }
  });
});

const owner = () => env.authenticatedContext(OWNER).firestore();
const other = () => env.authenticatedContext(OTHER).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

describe('own tree', () => {
  test('the owner reads their lists and items, one by one and as queries', async () => {
    const db = owner();
    await assertSucceeds(getDoc(doc(db, `users/${OWNER}/lists/plants`)));
    await assertSucceeds(getDoc(doc(db, `users/${OWNER}/lists/plants/items/fern`)));
    await assertSucceeds(getDocs(collection(db, `users/${OWNER}/lists`)));
    await assertSucceeds(getDocs(collection(db, `users/${OWNER}/lists/plants/items`)));
  });

  test('the owner creates, updates and deletes a list', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/books`);
    await assertSucceeds(setDoc(ref, list('books')));
    await assertSucceeds(setDoc(ref, list('books', { schemaRevision: 3, name: 'Books' })));
    await assertSucceeds(deleteDoc(ref));
  });

  test('the owner creates, updates and deletes an item', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/plants/items/ivy`);
    await assertSucceeds(setDoc(ref, item('ivy', 'plants')));
    await assertSucceeds(setDoc(ref, item('ivy', 'plants', { _rev: 3 })));
    await assertSucceeds(deleteDoc(ref));
  });

  test('a list and its items in one batch, as createList writes them', async () => {
    const db = owner();
    const batch = writeBatch(db);
    batch.set(doc(db, `users/${OWNER}/lists/books`), list('books'));
    for (const id of ['b1', 'b2', 'b3']) {
      batch.set(doc(db, `users/${OWNER}/lists/books/items/${id}`), item(id, 'books'));
    }
    await assertSucceeds(batch.commit());
  });

  test('keys of a newer build on a list are allowed', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/books`);
    await assertSucceeds(setDoc(ref, list('books', { sortOrder: 4, archived: false })));
  });

  test('an item without `_rev` is allowed', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/plants/items/ivy`);
    await assertSucceeds(setDoc(ref, without(item('ivy', 'plants'), '_rev')));
  });

  test('hidden values with the nested-array encoding are allowed', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/plants/items/ivy`);
    await assertSucceeds(
      setDoc(
        ref,
        item('ivy', 'plants', {
          values: {
            name: 'ivy',
            tags: ['green', 'climbing'],
            _legacy: {
              tags: [{ __array: ['old', 'tags'] }, { __array: [] }],
              checklist: [{ __array: [{ text: 'water', done: true }] }],
            },
          },
        }),
      ),
    );
  });
});

describe('other users and signed-out clients', () => {
  test('another user cannot read the owner\'s tree', async () => {
    const db = other();
    await assertFails(getDoc(doc(db, `users/${OWNER}/lists/plants`)));
    await assertFails(getDoc(doc(db, `users/${OWNER}/lists/plants/items/fern`)));
    await assertFails(getDocs(collection(db, `users/${OWNER}/lists`)));
    await assertFails(getDocs(collection(db, `users/${OWNER}/lists/plants/items`)));
  });

  test('another user cannot write the owner\'s tree', async () => {
    const db = other();
    await assertFails(setDoc(doc(db, `users/${OWNER}/lists/books`), list('books')));
    await assertFails(setDoc(doc(db, `users/${OWNER}/lists/plants`), list('plants')));
    await assertFails(deleteDoc(doc(db, `users/${OWNER}/lists/plants`)));
    await assertFails(
      setDoc(doc(db, `users/${OWNER}/lists/plants/items/ivy`), item('ivy', 'plants')),
    );
    await assertFails(deleteDoc(doc(db, `users/${OWNER}/lists/plants/items/fern`)));
  });

  test('a signed-out client can neither read nor write', async () => {
    const db = signedOut();
    await assertFails(getDoc(doc(db, `users/${OWNER}/lists/plants`)));
    await assertFails(getDocs(collection(db, `users/${OWNER}/lists`)));
    await assertFails(getDoc(doc(db, `users/${OWNER}/lists/plants/items/fern`)));
    await assertFails(setDoc(doc(db, `users/${OWNER}/lists/books`), list('books')));
    await assertFails(
      setDoc(doc(db, `users/${OWNER}/lists/plants/items/ivy`), item('ivy', 'plants')),
    );
    await assertFails(deleteDoc(doc(db, `users/${OWNER}/lists/plants`)));
  });

  // users/{uid} itself is the starter-lists marker (tested below).
  test('nothing else outside users/{uid}/lists is open, not even to the owner', async () => {
    const db = owner();
    await assertFails(setDoc(doc(db, `users/${OWNER}`), { name: 'x' }));
    await assertFails(setDoc(doc(db, `users/${OWNER}/settings/app`), { theme: 'dark' }));
    await assertFails(setDoc(doc(db, 'shared/x'), { a: 1 }));
    await assertFails(getDocs(collection(db, 'users')));
  });
});

describe('list shape', () => {
  const ref = () => doc(owner(), `users/${OWNER}/lists/books`);

  test('the document id must equal the `id` field', async () => {
    await assertFails(setDoc(ref(), list('plants')));
  });

  for (const key of ['id', 'icon', 'color', 'fields', 'view', 'updatedAt']) {
    test(`the required key "${key}" must be present`, async () => {
      await assertFails(setDoc(ref(), without(list('books'), key)));
    });
  }

  test('wrong types are refused', async () => {
    await assertFails(setDoc(ref(), list('books', { fields: { name: 'text' } })));
    await assertFails(setDoc(ref(), list('books', { view: 'checklist' })));
    await assertFails(setDoc(ref(), list('books', { icon: 7 })));
    await assertFails(setDoc(ref(), list('books', { behaviors: 'none' })));
    await assertFails(setDoc(ref(), list('books', { schemaRevision: '2' })));
    await assertFails(setDoc(ref(), list('books', { updatedAt: new Date() })));
  });

  test('ids longer than 128 characters are refused', async () => {
    const longId = 'x'.repeat(129);
    await assertFails(
      setDoc(doc(owner(), `users/${OWNER}/lists/${longId}`), list(longId)),
    );
  });

  // T-14 R4: no count caps; the app accepts any number of fields and keeps
  // unknown keys, so the rules must too.
  test('no count limits on keys, fields or behaviors', async () => {
    const extra = Object.fromEntries(Array.from({ length: 60 }, (_, i) => [`k${i}`, i]));
    await assertSucceeds(setDoc(ref(), list('books', extra)));
    const fields = Array.from({ length: 150 }, (_, i) => ({ key: `f${i}`, type: 'text' }));
    await assertSucceeds(setDoc(ref(), list('books', { fields })));
    const behaviors = Array.from({ length: 60 }, () => ({ kind: 'clearCompleted' }));
    await assertSucceeds(setDoc(ref(), list('books', { behaviors })));
  });

  test('an update is checked like a create', async () => {
    await assertFails(
      setDoc(doc(owner(), `users/${OWNER}/lists/plants`), without(list('plants'), 'view')),
    );
  });
});

describe('item shape', () => {
  const ref = () => doc(owner(), `users/${OWNER}/lists/plants/items/ivy`);

  test('the document id must equal the `id` field', async () => {
    await assertFails(setDoc(ref(), item('fern', 'plants')));
  });

  test('`listId` must equal the parent list', async () => {
    await assertFails(setDoc(ref(), item('ivy', 'books')));
  });

  for (const key of ['id', 'listId', 'values', 'createdAt', 'updatedAt']) {
    test(`the required key "${key}" must be present`, async () => {
      await assertFails(setDoc(ref(), without(item('ivy', 'plants'), key)));
    });
  }

  test('wrong types are refused', async () => {
    await assertFails(setDoc(ref(), item('ivy', 'plants', { values: ['fern'] })));
    await assertFails(setDoc(ref(), item('ivy', 'plants', { createdAt: 5 })));
    await assertFails(setDoc(ref(), item('ivy', 'plants', { _rev: '2' })));
  });

  // T-14 R4: an item keeps hidden values when its list loses fields, so it
  // can carry many more value keys than the list has fields.
  test('no count limits on keys or values', async () => {
    const extra = Object.fromEntries(Array.from({ length: 10 }, (_, i) => [`k${i}`, i]));
    await assertSucceeds(setDoc(ref(), item('ivy', 'plants', extra)));
  });

  test('an app-produced item with many hidden values is allowed', async () => {
    // As the store writes it after a list dropped 250 fields and changed the
    // type of 50 more: the dropped values stay as hidden keys, the changed
    // ones are archived in `_legacy` with the nested-array encoding.
    const values = { name: 'ivy' };
    for (let i = 0; i < 250; i++) values[`old${i}`] = `value ${i}`;
    const legacy = {};
    for (let i = 0; i < 50; i++) legacy[`tags${i}`] = [{ __array: ['a', 'b'] }];
    values._legacy = legacy;
    await assertSucceeds(setDoc(ref(), item('ivy', 'plants', { values })));
  });
});

// T-17, Q-22 D: users/{uid} is the starter-lists marker.
describe('starter-lists marker', () => {
  const marker = { starterSeededAt: '2026-03-01T00:00:00.000Z' };
  const ref = (db, uid = OWNER) => doc(db, `users/${uid}`);

  test('the owner creates and reads their marker', async () => {
    await assertSucceeds(setDoc(ref(owner()), marker));
    await assertSucceeds(getDoc(ref(owner())));
  });

  test('the owner reads a missing marker (a new account)', async () => {
    await assertSucceeds(getDoc(ref(owner())));
  });

  test('the marker and the starter lists in one batch, as seeding writes them', async () => {
    const db = owner();
    const batch = writeBatch(db);
    batch.set(ref(db), marker);
    for (const id of ['list-a', 'list-b', 'list-c', 'list-d']) {
      batch.set(
        doc(db, `users/${OWNER}/lists/${id}`),
        list(id, { templateId: 'builtin.tasks', _createdAt: '2026-03-01T00:00:00.001Z' }),
      );
    }
    await assertSucceeds(batch.commit());
  });

  test('the marker is never changed or deleted', async () => {
    await assertSucceeds(setDoc(ref(owner()), marker));
    await assertFails(setDoc(ref(owner()), { starterSeededAt: '2026-04-01T00:00:00.000Z' }));
    await assertFails(deleteDoc(ref(owner())));
  });

  test('a malformed marker is refused', async () => {
    await assertFails(setDoc(ref(owner()), {}));
    await assertFails(setDoc(ref(owner()), { starterSeededAt: 5 }));
  });

  test('other users and signed-out clients can neither read nor write it', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(ref(context.firestore()), marker);
    });
    await assertFails(getDoc(ref(other())));
    await assertFails(getDoc(ref(signedOut())));
    await assertFails(setDoc(ref(other()), marker));
    await assertFails(setDoc(ref(other(), 'new-uid'), marker));
    await assertFails(setDoc(ref(signedOut(), 'new-uid'), marker));
    await assertFails(deleteDoc(ref(other())));
  });

  test('an anonymous user has their own marker (T-18)', async () => {
    const anon = env
      .authenticatedContext('anon-uid', { firebase: { sign_in_provider: 'anonymous' } })
      .firestore();
    await assertSucceeds(setDoc(ref(anon, 'anon-uid'), marker));
    await assertFails(getDoc(ref(anon)));
  });
});

describe('list order key', () => {
  test('`_createdAt` must be a string when present', async () => {
    const ref = doc(owner(), `users/${OWNER}/lists/books`);
    await assertSucceeds(setDoc(ref, list('books', { _createdAt: '2026-03-01T00:00:00.000Z' })));
    await assertFails(setDoc(ref, list('books', { _createdAt: 5 })));
  });
});
