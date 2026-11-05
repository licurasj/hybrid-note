// A limited tier through handleAiCommand on the Firestore emulator: what T-18's
// demo tier will rely on, now that the owner has no limits to test with (Q-63).
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { MODELS, TIERS, ceilingMicros, type TierLimits } from '../src/config';
import { reasonOf } from '../src/errors';
import { handleAiCommand, type AiResponse } from '../src/handler';
import { FakeProvider } from '../src/provider/fake';
import { allow, clearFirestore, db, today } from './helpers';

const UID = 'limited-test-uid';
const model = MODELS.fake;
const CEILING = ceilingMicros(model);
const BUDGET = 1_000_000;
const limits: TierLimits = { ...TIERS.owner, requestsPerDay: 100, pools: ['global'] };

const userDoc = () => db().collection('aiUsageUser').doc(`${UID}_${today()}`);
const poolDoc = () => db().collection('aiUsagePool').doc(`global_${today()}`);

let requests = 0;

/** One request, with the tier's refusal reason in place of an answer. */
async function call(): Promise<{ ok: true; result: AiResponse } | { ok: false; reason: string }> {
  try {
    const result = await handleAiCommand(
      {
        uid: UID,
        appCheckTokenPresent: false,
        data: { prompt: 'eggs', platform: 'android', locale: 'en', lists: [], openList: null },
      },
      {
        db: db(),
        provider: new FakeProvider(),
        model,
        limits,
        log: () => {},
        now: () => new Date(),
        newRequestId: () => `limited-${++requests}`,
      },
    );
    return { ok: true, result };
  } catch (error) {
    return { ok: false, reason: reasonOf(error) };
  }
}

beforeEach(async () => {
  await clearFirestore();
  await allow(UID);
});

describe('a limited tier', () => {
  test('is refused at its daily count', async () => {
    await userDoc().set({ count: 100 });
    assert.deepEqual(await call(), { ok: false, reason: 'dailyCount' });
  });

  test('is refused at its pool stop', async () => {
    await poolDoc().set({ spentMicros: BUDGET - CEILING + 1, reservedMicros: 0 });
    assert.deepEqual(await call(), { ok: false, reason: 'globalBudget' });
  });

  test('a finished call moves its cost from reserved to spent in the pool', async () => {
    const r = await call();
    assert.equal(r.ok, true);
    const pool = await poolDoc().get();
    assert.equal(pool.get('reservedMicros'), 0);
    assert.ok(pool.get('spentMicros') > 0);
  });

  test('10 parallel calls with 3 left: 3 pass, the count ends at 100', async () => {
    await userDoc().set({ count: 97 });
    const results = await Promise.all(Array.from({ length: 10 }, () => call()));
    assert.equal(results.filter((r) => r.ok).length, 3);
    assert.ok(results.every((r) => r.ok || r.reason === 'dailyCount'));
    assert.equal((await userDoc().get()).get('count'), 100);
  });

  // A finished call settles to its real cost and frees the rest of its
  // reservation, so more than 3 may pass when calls overlap only partly; the
  // strict race (exactly 3) is in caps.test.ts. Here: no overshoot, nothing left
  // reserved, and the pool holds exactly the costs returned.
  test('10 parallel calls with room for 3 ceilings: spent stays under the stop', async () => {
    const start = BUDGET - 3 * CEILING;
    await poolDoc().set({ spentMicros: start, reservedMicros: 0 });
    const results = await Promise.all(Array.from({ length: 10 }, () => call()));
    const passed = results.flatMap((r) => (r.ok ? [r.result] : []));
    assert.ok(passed.length >= 3);
    assert.ok(results.every((r) => r.ok || r.reason === 'globalBudget'));
    const pool = await poolDoc().get();
    assert.equal(pool.get('reservedMicros'), 0);
    assert.ok(pool.get('spentMicros') <= BUDGET);
    const returned = passed.reduce((sum, r) => sum + Math.round(r.usage.costUsd * 1e6), 0);
    assert.equal(pool.get('spentMicros'), start + returned);
  });
});
