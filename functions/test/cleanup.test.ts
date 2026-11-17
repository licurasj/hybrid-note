// The demo's clean-up job (T-18 unit 1) on the Auth and Firestore emulators:
// old anonymous accounts go with their aiUsageUser documents, accounts with a
// sign-in provider never do, and one failure neither stops the run nor
// survives the next one.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getAuth } from 'firebase-admin/auth';

import { cleanUpAnonymous, type CleanupAuth } from '../src/cleanup';
import { clearAuth, clearFirestore, db, newAnonymousUser, newUser } from './helpers';

const HOUR = 3_600_000;
const auth = () => {
  db(); // initialises the Admin app
  return getAuth();
};
const later = (hours: number) => new Date(Date.now() + hours * HOUR);
const usage = () => db().collection('aiUsageUser');

async function exists(uid: string): Promise<boolean> {
  try {
    await auth().getUser(uid);
    return true;
  } catch {
    return false;
  }
}

/** Usage documents on two days, like a visitor who came back after midnight UTC. */
async function addUsage(uid: string): Promise<void> {
  await usage().doc(`${uid}_2026-11-16`).set({ count: 3 });
  await usage().doc(`${uid}_2026-11-17`).set({ count: 1 });
}

async function usageIds(): Promise<string[]> {
  return (await usage().get()).docs.map((d) => d.id).sort();
}

/** A Google account, as Google sign-in leaves it: a google.com provider. */
async function googleUser(): Promise<string> {
  const uid = `google-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const result = await auth().importUsers([
    {
      uid,
      email: `${uid}@example.test`,
      providerData: [{ uid: `g-${uid}`, providerId: 'google.com', email: `${uid}@example.test` }],
    },
  ]);
  assert.equal(result.failureCount, 0);
  return uid;
}

beforeEach(async () => {
  await clearFirestore();
  await clearAuth();
});

describe('the clean-up job', () => {
  test('anonymous accounts younger than 24 hours stay', async () => {
    const visitor = await newAnonymousUser();
    await addUsage(visitor.uid);
    const result = await cleanUpAnonymous(auth(), db(), later(23));
    assert.deepEqual(result, { found: 0, deleted: 0, failed: 0, usageDocs: 0 });
    assert.equal(await exists(visitor.uid), true);
    assert.equal((await usageIds()).length, 2);
  });

  test('older anonymous accounts go with their usage documents; others stay', async () => {
    const a = await newAnonymousUser();
    const b = await newAnonymousUser();
    const google = await googleUser();
    const email = await newUser();
    for (const uid of [a.uid, b.uid, google, email.uid]) await addUsage(uid);

    const result = await cleanUpAnonymous(auth(), db(), later(25));
    assert.deepEqual(result, { found: 2, deleted: 2, failed: 0, usageDocs: 4 });
    assert.equal(await exists(a.uid), false);
    assert.equal(await exists(b.uid), false);
    assert.equal(await exists(google), true);
    assert.equal(await exists(email.uid), true);
    assert.deepEqual(
      await usageIds(),
      [`${google}_2026-11-16`, `${google}_2026-11-17`, `${email.uid}_2026-11-16`, `${email.uid}_2026-11-17`].sort(),
    );
  });

  test('an account with a sign-in provider is never removed, whatever its age', async () => {
    const google = await googleUser();
    const email = await newUser();
    const result = await cleanUpAnonymous(auth(), db(), later(24 * 1000));
    assert.equal(result.found, 0);
    assert.equal(await exists(google), true);
    assert.equal(await exists(email.uid), true);
  });

  test('a failure on one account does not stop the others; the next run retries it', async () => {
    const visitors = await Promise.all([newAnonymousUser(), newAnonymousUser(), newAnonymousUser()]);
    for (const v of visitors) await addUsage(v.uid);
    const failing = visitors[1].uid;
    const real = auth();
    const flaky: CleanupAuth = {
      listUsers: (max, token) => real.listUsers(max, token),
      deleteUser: async (uid) => {
        if (uid === failing) throw new Error('injected failure');
        return real.deleteUser(uid);
      },
    };

    const first = await cleanUpAnonymous(flaky, db(), later(25));
    assert.deepEqual([first.found, first.deleted, first.failed], [3, 2, 1]);
    assert.equal(await exists(visitors[0].uid), false);
    assert.equal(await exists(failing), true);
    assert.equal(await exists(visitors[2].uid), false);

    const second = await cleanUpAnonymous(real, db(), later(25));
    assert.deepEqual([second.found, second.deleted, second.failed], [1, 1, 0]);
    assert.equal(await exists(failing), false);
    assert.deepEqual(await usageIds(), []);
  });

  test('a usage-document failure keeps the account for the next run', async () => {
    const visitor = await newAnonymousUser();
    await addUsage(visitor.uid);
    const real = db();
    let fail = true;
    const flakyDb = new Proxy(real, {
      get(target, key, receiver) {
        if (key === 'batch' && fail) {
          return () => ({ delete() {}, commit: async () => { throw new Error('injected failure'); } });
        }
        const value = Reflect.get(target, key, receiver);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });

    const first = await cleanUpAnonymous(auth(), flakyDb, later(25));
    assert.deepEqual([first.found, first.deleted, first.failed], [1, 0, 1]);
    assert.equal(await exists(visitor.uid), true);
    assert.equal((await usageIds()).length, 2);

    fail = false;
    const second = await cleanUpAnonymous(auth(), flakyDb, later(25));
    assert.deepEqual([second.deleted, second.usageDocs], [1, 2]);
    assert.equal(await exists(visitor.uid), false);
    assert.deepEqual(await usageIds(), []);
  });
});
