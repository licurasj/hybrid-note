// The demo's clean-up job (T-18 unit 1, fixes M2 to M4) on the Auth and
// Firestore emulators: old anonymous accounts are retired and deleted, their
// aiUsageUser documents go at a later run after the drain, accounts with a
// sign-in provider never go (also when they gain one after the listing), a
// visitor's count is never reset while the account can call, one failure
// neither stops the run nor survives the next one, and a run is bounded.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getAuth } from 'firebase-admin/auth';

import { reserve, settle } from '../src/caps';
import { cleanUpAnonymous, type CleanupAuth, type CleanupResult } from '../src/cleanup';
import { MODELS, TIERS } from '../src/config';
import { reasonOf } from '../src/errors';
import { clearAuth, clearFirestore, db, newAnonymousUser, newUser, today } from './helpers';

const HOUR = 3_600_000;
const auth = () => {
  db(); // initialises the Admin app
  return getAuth();
};
const later = (hours: number) => new Date(Date.now() + hours * HOUR);
const usage = () => db().collection('aiUsageUser');
const retired = () => db().collection('aiDemoRetired');
const todayDoc = (uid: string) => usage().doc(`${uid}_${today()}`);
const EMPTY: CleanupResult = { found: 0, deleted: 0, skipped: 0, failed: 0, purged: 0, usageDocs: 0, remaining: 0 };
const result = (counts: Partial<CleanupResult>): CleanupResult => ({ ...EMPTY, ...counts });

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

/** A demo call of `uid` now: 'ok', or the refusal reason. */
async function demoCall(uid: string): Promise<string> {
  try {
    await reserve(db(), uid, 'demo', TIERS.demo, MODELS.fake, new Date());
    return 'ok';
  } catch (error) {
    return reasonOf(error);
  }
}

/** The real Auth with some calls replaced. */
function authWith(overrides: Partial<CleanupAuth>): CleanupAuth {
  const real = auth();
  return {
    listUsers: (max, token) => real.listUsers(max, token),
    getUser: (uid) => real.getUser(uid),
    deleteUser: (uid) => real.deleteUser(uid),
    ...overrides,
  };
}

/** A Google account, as Google sign-in leaves it: a google.com provider. */
async function googleUser(): Promise<string> {
  const uid = `google-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const imported = await auth().importUsers([
    {
      uid,
      email: `${uid}@example.test`,
      providerData: [{ uid: `g-${uid}`, providerId: 'google.com', email: `${uid}@example.test` }],
    },
  ]);
  assert.equal(imported.failureCount, 0);
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
    assert.deepEqual(await cleanUpAnonymous(auth(), db(), later(23)), EMPTY);
    assert.equal(await exists(visitor.uid), true);
    assert.equal((await usageIds()).length, 2);
  });

  test('older anonymous accounts go, their usage documents after the drain; others stay', async () => {
    const a = await newAnonymousUser();
    const b = await newAnonymousUser();
    const google = await googleUser();
    const email = await newUser();
    for (const uid of [a.uid, b.uid, google, email.uid]) await addUsage(uid);

    const first = await cleanUpAnonymous(auth(), db(), later(25));
    assert.deepEqual(first, result({ found: 2, deleted: 2 }));
    assert.equal(await exists(a.uid), false);
    assert.equal(await exists(b.uid), false);
    assert.equal((await usageIds()).length, 8, 'usage stays until no token of the account is valid');
    // One hour later: still inside the drain.
    assert.deepEqual(await cleanUpAnonymous(auth(), db(), later(26)), EMPTY);

    const second = await cleanUpAnonymous(auth(), db(), later(28));
    assert.deepEqual(second, result({ purged: 2, usageDocs: 4 }));
    assert.equal(await exists(google), true);
    assert.equal(await exists(email.uid), true);
    assert.deepEqual(
      await usageIds(),
      [`${google}_2026-11-16`, `${google}_2026-11-17`, `${email.uid}_2026-11-16`, `${email.uid}_2026-11-17`].sort(),
    );
    assert.equal((await retired().get()).size, 0);
  });

  test('an account with a sign-in provider is never removed, whatever its age', async () => {
    const google = await googleUser();
    const email = await newUser();
    const run = await cleanUpAnonymous(auth(), db(), later(24 * 1000));
    assert.equal(run.found, 0);
    assert.equal(await exists(google), true);
    assert.equal(await exists(email.uid), true);
  });

  test('an account that gains a provider after the listing is kept (M2)', async () => {
    const visitor = await newAnonymousUser();
    await addUsage(visitor.uid);
    const real = auth();
    const linking = authWith({
      listUsers: async (max, token) => {
        const page = await real.listUsers(max, token);
        // The visitor links Google between the listing and the delete.
        await real.updateUser(visitor.uid, {
          providerToLink: { uid: `g-${visitor.uid}`, providerId: 'google.com', email: `${visitor.uid}@example.test` },
        });
        return page;
      },
    });

    const run = await cleanUpAnonymous(linking, db(), later(25));
    assert.deepEqual(run, result({ found: 1, skipped: 1 }));
    assert.equal(await exists(visitor.uid), true);
    assert.equal((await usageIds()).length, 2);
    assert.equal((await retired().get()).size, 0, 'the retired mark is taken back');
  });

  test('a visitor at 20 calls keeps the count when the Auth delete fails, and gets no new call (M3)', async () => {
    const visitor = await newAnonymousUser();
    await todayDoc(visitor.uid).set({ count: 20 });
    const failing = authWith({
      deleteUser: async () => {
        throw new Error('injected failure');
      },
    });

    const run = await cleanUpAnonymous(failing, db(), later(25));
    assert.deepEqual(run, result({ found: 1, failed: 1 }));
    assert.equal(await exists(visitor.uid), true);
    assert.equal((await todayDoc(visitor.uid).get()).get('count'), 20, 'the count is not reset');
    assert.equal(await demoCall(visitor.uid), 'signIn', 'a retired account gets no call, so no fresh count');

    // After the drain the account is still in Auth, so its usage stays.
    const stillThere = await cleanUpAnonymous(failing, db(), later(31));
    assert.equal(stillThere.purged, 0);
    assert.equal((await todayDoc(visitor.uid).get()).get('count'), 20);

    // A working run deletes it, and the run after the drain removes the usage.
    await cleanUpAnonymous(auth(), db(), later(31));
    assert.equal(await exists(visitor.uid), false);
    const purged = await cleanUpAnonymous(auth(), db(), later(34));
    assert.equal(purged.purged, 1);
    assert.deepEqual(await usageIds(), []);
  });

  test("a deleted account's still-valid token cannot recreate its count; a settle in flight lands before the purge (M3)", async () => {
    const visitor = await newAnonymousUser();
    await todayDoc(visitor.uid).set({ count: 19 });
    const inFlight = await reserve(db(), visitor.uid, 'demo', TIERS.demo, MODELS.fake, new Date());

    await cleanUpAnonymous(auth(), db(), later(25));
    assert.equal(await exists(visitor.uid), false);
    // The callable framework does not check revocation, so a cached token still reaches reserve.
    assert.equal(await demoCall(visitor.uid), 'signIn');
    await settle(db(), inFlight, 1234, new Date());
    const kept = await todayDoc(visitor.uid).get();
    assert.deepEqual([kept.get('count'), kept.get('spentMicros')], [20, 1234]);

    await cleanUpAnonymous(auth(), db(), later(28));
    assert.deepEqual(await usageIds(), []);
    assert.equal((await retired().get()).size, 0);
  });

  test('a failure on one account does not stop the others; the next run retries it', async () => {
    const visitors = await Promise.all([newAnonymousUser(), newAnonymousUser(), newAnonymousUser()]);
    for (const v of visitors) await addUsage(v.uid);
    const failing = visitors[1].uid;
    const real = auth();
    const flaky = authWith({
      deleteUser: async (uid) => {
        if (uid === failing) throw new Error('injected failure');
        return real.deleteUser(uid);
      },
    });

    const first = await cleanUpAnonymous(flaky, db(), later(25));
    assert.deepEqual([first.found, first.deleted, first.failed], [3, 2, 1]);
    assert.equal(await exists(visitors[0].uid), false);
    assert.equal(await exists(failing), true);
    assert.equal(await exists(visitors[2].uid), false);

    const second = await cleanUpAnonymous(real, db(), later(28));
    assert.deepEqual([second.found, second.deleted, second.purged], [1, 1, 2]);
    assert.equal(await exists(failing), false);
    const third = await cleanUpAnonymous(real, db(), later(31));
    assert.equal(third.purged, 1);
    assert.deepEqual(await usageIds(), []);
  });

  test('a usage-document failure keeps the retired mark for the next run', async () => {
    const visitor = await newAnonymousUser();
    await addUsage(visitor.uid);
    await cleanUpAnonymous(auth(), db(), later(25));
    const real = db();
    let fail = true;
    const flakyDb = new Proxy(real, {
      get(target, key, receiver) {
        if (key === 'batch' && fail) {
          return () => ({
            delete() {},
            commit: async () => {
              throw new Error('injected failure');
            },
          });
        }
        const value = Reflect.get(target, key, receiver);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });

    const first = await cleanUpAnonymous(auth(), flakyDb, later(28));
    assert.deepEqual([first.purged, first.failed], [0, 1]);
    assert.equal((await usageIds()).length, 2);
    assert.equal((await retired().get()).size, 1);

    fail = false;
    const second = await cleanUpAnonymous(auth(), flakyDb, later(28));
    assert.deepEqual([second.purged, second.usageDocs], [1, 2]);
    assert.deepEqual(await usageIds(), []);
    assert.equal((await retired().get()).size, 0);
  });

  test('one run is bounded by a cap and a time budget; the next run carries on (M4)', async () => {
    const visitors = await Promise.all(Array.from({ length: 5 }, () => newAnonymousUser()));

    const capped = await cleanUpAnonymous(auth(), db(), later(25), { maxAccounts: 2, parallel: 2 });
    assert.deepEqual([capped.found, capped.deleted], [2, 2]);

    // A clock that is out of time once the first chunk of two is done.
    let chunks = 0;
    const timed = await cleanUpAnonymous(
      authWith({
        deleteUser: async (uid) => {
          chunks++;
          return auth().deleteUser(uid);
        },
      }),
      db(),
      later(25),
      { parallel: 2, budgetMs: 1000, clock: () => (chunks >= 2 ? 1_000_000 : 0) },
    );
    assert.deepEqual([timed.found, timed.deleted, timed.remaining], [3, 2, 1]);

    const rest = await cleanUpAnonymous(auth(), db(), later(25));
    assert.deepEqual([rest.found, rest.deleted, rest.remaining], [1, 1, 0]);
    for (const v of visitors) assert.equal(await exists(v.uid), false);
  });
});
