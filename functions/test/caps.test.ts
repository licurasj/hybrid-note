// Cap reservation and settlement (D-13, Q-29 B) on the Firestore emulator:
// parallel transactions at the edge of each cap never overshoot it.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { countOnly, dayOf, reserve, settle } from '../src/caps';
import { MODELS, TIERS, ceilingMicros } from '../src/config';
import { reasonOf } from '../src/errors';
import { clearFirestore, db } from './helpers';

const model = MODELS.fake;
const limits = TIERS.owner;
const CEILING = ceilingMicros(model);
const BUDGET = 1_000_000; // $1 in microdollars
const now = new Date();
const day = dayOf(now);

const userDoc = (uid: string) => db().collection('aiUsageUser').doc(`${uid}_${day}`);
const poolDoc = () => db().collection('aiUsagePool').doc(`global_${day}`);

async function settled<T>(promises: Promise<T>[]) {
  const results = await Promise.allSettled(promises);
  return {
    ok: results.filter((r) => r.status === 'fulfilled').map((r) => (r as PromiseFulfilledResult<T>).value),
    reasons: results.filter((r) => r.status === 'rejected').map((r) => reasonOf((r as PromiseRejectedResult).reason)),
  };
}

beforeEach(async () => {
  await clearFirestore();
});

describe('per-user daily count', () => {
  test('20 parallel calls with 3 left: exactly 3 pass, the count ends at 100', async () => {
    await userDoc('u1').set({ day, tier: 'owner', count: 97 });
    const { ok, reasons } = await settled(
      Array.from({ length: 20 }, () => reserve(db(), 'u1', 'owner', limits, model, now)),
    );
    assert.equal(ok.length, 3);
    assert.deepEqual(new Set(reasons), new Set(['dailyCount']));
    assert.equal((await userDoc('u1').get()).get('count'), 100);
    assert.equal((await poolDoc().get()).get('reservedMicros'), 3 * CEILING);
  });

  test('a refused call changes nothing', async () => {
    await userDoc('u1').set({ day, tier: 'owner', count: 100 });
    await assert.rejects(reserve(db(), 'u1', 'owner', limits, model, now), (e) => reasonOf(e) === 'dailyCount');
    assert.equal((await userDoc('u1').get()).get('count'), 100);
    assert.equal((await poolDoc().get()).exists, false);
  });

  test('countOnly counts refused requests and stops at the limit', async () => {
    await countOnly(db(), 'u2', 'owner', limits, now);
    assert.equal((await userDoc('u2').get()).get('count'), 1);
    await userDoc('u2').set({ count: 100 }, { merge: true });
    await Promise.all(Array.from({ length: 5 }, () => countOnly(db(), 'u2', 'owner', limits, now)));
    assert.equal((await userDoc('u2').get()).get('count'), 100);
  });
});

describe('global $1/day stop', () => {
  test('20 parallel calls with room for 3 ceilings: exactly 3 pass, no overshoot', async () => {
    await poolDoc().set({ day, pool: 'global', spentMicros: BUDGET - 3 * CEILING, reservedMicros: 0 });
    const { ok, reasons } = await settled(
      Array.from({ length: 20 }, (_, i) => reserve(db(), `p${i}`, 'owner', limits, model, now)),
    );
    assert.equal(ok.length, 3);
    assert.deepEqual(new Set(reasons), new Set(['globalBudget']));
    const pool = await poolDoc().get();
    assert.equal(pool.get('reservedMicros'), 3 * CEILING);
    assert.ok(pool.get('spentMicros') + pool.get('reservedMicros') <= BUDGET);

    // Settling to real costs below the ceiling frees the difference.
    await Promise.all(ok.map((r) => settle(db(), r, 1000, now)));
    const after = await poolDoc().get();
    assert.equal(after.get('reservedMicros'), 0);
    assert.equal(after.get('spentMicros'), BUDGET - 3 * CEILING + 3000);
    assert.ok(after.get('spentMicros') <= BUDGET);
  });

  test('reserve, call and settle in parallel up to the stop: spent never passes $1', async () => {
    await poolDoc().set({ day, pool: 'global', spentMicros: BUDGET - 10 * CEILING, reservedMicros: 0 });
    // Each call costs its full ceiling, the worst case.
    const { ok } = await settled(
      Array.from({ length: 30 }, async (_, i) => {
        const r = await reserve(db(), `q${i}`, 'owner', limits, model, now);
        await settle(db(), r, CEILING, now);
        return r;
      }),
    );
    assert.equal(ok.length, 10);
    const pool = await poolDoc().get();
    assert.equal(pool.get('spentMicros'), BUDGET);
    assert.equal(pool.get('reservedMicros'), 0);
  });

  test('the ceiling of the fake model matches Haiku-like prices', () => {
    // 20k input at $0.10/MTok + 4k output at $0.50/MTok = $0.004.
    assert.equal(CEILING, 4000);
  });
});
