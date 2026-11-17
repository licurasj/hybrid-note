// The real demo tier (T-18 unit 1, Q-83 A) through handleAiCommand on the
// Firestore emulator: no Deps.limits, so TIERS.demo and POOLS.global are the
// ones in force.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { reserve, settle } from '../src/caps';
import { MODELS, POOLS, TIERS, ceilingMicros } from '../src/config';
import { reasonOf } from '../src/errors';
import { handleAiCommand, type AiResponse } from '../src/handler';
import { FakeProvider } from '../src/provider/fake';
import { allow, clearFirestore, db, request, today } from './helpers';

const model = MODELS.fake;
const CEILING = ceilingMicros(model);
const BUDGET = Math.round(POOLS.global.usdPerDay * 1e6);

const userDoc = (uid: string) => db().collection('aiUsageUser').doc(`${uid}_${today()}`);
const poolDoc = () => db().collection('aiUsagePool').doc(`global_${today()}`);

let requests = 0;

type Result = { ok: true; result: AiResponse; tier?: string } | { ok: false; reason: string; tier?: string };

/** One request as `uid` signed in with `provider`; the logged tier comes back too. */
async function call(uid: string, provider: string | undefined, data: unknown = request('eggs')): Promise<Result> {
  let tier: string | undefined;
  try {
    const result = await handleAiCommand(
      { uid, signInProvider: provider, appCheckTokenPresent: false, data },
      {
        db: db(),
        provider: new FakeProvider(),
        model,
        log: (_message, entry) => (tier = entry.tier),
        now: () => new Date(),
        newRequestId: () => `demo-${++requests}`,
      },
    );
    return { ok: true, result, tier };
  } catch (error) {
    return { ok: false, reason: reasonOf(error), tier };
  }
}

const anon = (uid: string, data?: unknown) => call(uid, 'anonymous', data);

beforeEach(async () => {
  await clearFirestore();
});

describe('who gets the demo tier', () => {
  test('an anonymous account, from the token alone', async () => {
    const r = await anon('visitor');
    assert.equal(r.ok, true);
    assert.equal(r.tier, 'demo');
    assert.equal((await userDoc('visitor').get()).get('tier'), 'demo');
    assert.equal((await poolDoc().get()).get('count'), 1);
  });

  test('an allowlist entry does not change an anonymous account: still demo', async () => {
    await allow('visitor', 'owner');
    assert.equal((await anon('visitor')).tier, 'demo');
  });

  test('a Google account not on the allowlist is still refused, and not counted', async () => {
    assert.deepEqual(await call('stranger', 'google.com'), { ok: false, reason: 'notAllowed', tier: undefined });
    assert.equal((await userDoc('stranger').get()).exists, false);
  });

  test('the owner is unchanged: no count, no pool', async () => {
    await allow('owner', 'owner');
    await userDoc('owner').set({ count: 5000 });
    await poolDoc().set({ spentMicros: BUDGET, reservedMicros: 0 });
    const r = await call('owner', 'google.com');
    assert.equal(r.ok, true);
    assert.equal(r.tier, 'owner');
    assert.equal((await poolDoc().get()).get('spentMicros'), BUDGET);
    assert.equal((await poolDoc().get()).get('count'), undefined);
  });
});

describe('the daily count: 20 per visitor per UTC day', () => {
  test('20 calls pass, the 21st is refused dailyCount', async () => {
    for (let i = 0; i < 20; i++) assert.equal((await anon('visitor')).ok, true, `call ${i + 1}`);
    assert.deepEqual(await anon('visitor'), { ok: false, reason: 'dailyCount', tier: 'demo' });
    assert.equal((await userDoc('visitor').get()).get('count'), 20);
    // Another visitor is not affected.
    assert.equal((await anon('other')).ok, true);
  });

  test('10 parallel calls with 3 left: 3 pass, the count ends at 20', async () => {
    await userDoc('visitor').set({ count: 17 });
    const results = await Promise.all(Array.from({ length: 10 }, () => anon('visitor')));
    assert.equal(results.filter((r) => r.ok).length, 3);
    assert.ok(results.every((r) => r.ok || r.reason === 'dailyCount'));
    assert.equal((await userDoc('visitor').get()).get('count'), 20);
  });
});

describe('the pool: global at $0.30 per UTC day', () => {
  test('refused globalBudget when the next ceiling would pass $0.30', async () => {
    await poolDoc().set({ spentMicros: BUDGET - CEILING + 1, reservedMicros: 0 });
    assert.deepEqual(await anon('visitor'), { ok: false, reason: 'globalBudget', tier: 'demo' });
    await poolDoc().set({ spentMicros: BUDGET - CEILING, reservedMicros: 0 });
    assert.equal((await anon('visitor')).ok, true);
  });

  test('20 parallel reservations with room for 3 ceilings: exactly 3, no overshoot', async () => {
    await poolDoc().set({ spentMicros: BUDGET - 3 * CEILING, reservedMicros: 0 });
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) => reserve(db(), `v${i}`, 'demo', TIERS.demo, model, new Date())),
    );
    const ok = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []));
    assert.equal(ok.length, 3);
    assert.ok(results.every((r) => r.status === 'fulfilled' || reasonOf(r.reason) === 'globalBudget'));
    assert.equal((await poolDoc().get()).get('reservedMicros'), 3 * CEILING);
    await Promise.all(ok.map((r) => settle(db(), r, CEILING, new Date())));
    const pool = await poolDoc().get();
    assert.equal(pool.get('spentMicros'), BUDGET);
    assert.equal(pool.get('reservedMicros'), 0);
  });

  test('30 visitors in parallel near the stop: spent stays at or under $0.30', async () => {
    const start = BUDGET - 3 * CEILING;
    await poolDoc().set({ spentMicros: start, reservedMicros: 0 });
    const results = await Promise.all(Array.from({ length: 30 }, (_, i) => anon(`p${i}`)));
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

describe('demo input limits', () => {
  test('a 1,000-character prompt passes, 1,001 is refused promptTooLong and counted', async () => {
    assert.equal((await anon('visitor', request('x'.repeat(1000)))).ok, true);
    assert.deepEqual(await anon('visitor', request('x'.repeat(1001))), { ok: false, reason: 'promptTooLong', tier: 'demo' });
    assert.equal((await userDoc('visitor').get()).get('count'), 2);
  });

  test('a context over 16,000 bytes is refused contextTooLarge; the owner still gets 32,000', async () => {
    // 20 items of 900 bytes: about 18,500 bytes of context.
    const items = Array.from({ length: 20 }, (_, i) => ({ id: `i${i}`, values: { name: 'y'.repeat(900) } }));
    const big = request('eggs', { openList: { definition: { id: 'grocery' }, items } });
    assert.deepEqual(await anon('visitor', big), { ok: false, reason: 'contextTooLarge', tier: 'demo' });
    await allow('owner', 'owner');
    assert.equal((await call('owner', 'google.com', big)).ok, true);
  });
});
