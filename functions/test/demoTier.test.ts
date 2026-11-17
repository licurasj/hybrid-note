// The real demo tier (T-18 unit 1, Q-83 A) through handleAiCommand on the
// Firestore emulator: no Deps.limits, so TIERS.demo and POOLS.global are the
// ones in force.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { reserve, settle } from '../src/caps';
import { APP_CHECK, MODELS, POOLS, TIERS, ceilingMicros } from '../src/config';
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
let providerCalls = 0;

/** The fake provider, counting its calls. */
class CountingProvider extends FakeProvider {
  override call(input: Parameters<FakeProvider['call']>[0]) {
    providerCalls++;
    return super.call(input);
  }
}

/** The App Check the framework would hand over: a verified web token unless said otherwise. */
type AppCheck = { verifiedAppId?: string; appCheckTokenPresent: boolean };
const VERIFIED_WEB: AppCheck = { verifiedAppId: APP_CHECK.web.appId, appCheckTokenPresent: true };

type Result = { ok: true; result: AiResponse; tier?: string } | { ok: false; reason: string; tier?: string };

/** One request as `uid` signed in with `provider`; the logged tier comes back too. */
async function call(
  uid: string,
  provider: string | undefined,
  data: unknown = request('eggs'),
  appCheck: AppCheck = VERIFIED_WEB,
): Promise<Result> {
  let tier: string | undefined;
  try {
    const result = await handleAiCommand(
      { uid, signInProvider: provider, ...appCheck, data },
      {
        db: db(),
        provider: new CountingProvider(),
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
  providerCalls = 0;
});

describe('App Check for anonymous callers (T-18 M1)', () => {
  const NO_TOKEN: AppCheck = { appCheckTokenPresent: false };
  const INVALID: AppCheck = { appCheckTokenPresent: true };

  test('a missing or invalid token is refused on both declared platforms: no provider call, nothing counted', async () => {
    for (const platform of ['android', 'web']) {
      for (const appCheck of [NO_TOKEN, INVALID]) {
        const r = await call('visitor', 'anonymous', request('eggs', { platform }), appCheck);
        assert.equal(r.ok, false, platform);
        assert.equal((r as { reason: string }).reason, 'appCheck');
      }
    }
    assert.equal(providerCalls, 0);
    assert.equal((await userDoc('visitor').get()).exists, false);
    assert.equal((await poolDoc().get()).exists, false);
  });

  test('a verified token of an unknown app is refused', async () => {
    const r = await call('visitor', 'anonymous', request('eggs'), { verifiedAppId: '1:9:web:other', appCheckTokenPresent: true });
    assert.equal((r as { reason: string }).reason, 'appCheck');
    assert.equal(providerCalls, 0);
  });

  test('a verified token passes, declared android or web', async () => {
    for (const platform of ['android', 'web']) {
      const r = await call('visitor', 'anonymous', request('eggs', { platform }));
      assert.equal(r.ok, true, platform);
    }
    assert.equal(providerCalls, 2);
    assert.equal((await userDoc('visitor').get()).get('count'), 2);
  });

  test('the owner on Android without a token is unchanged (monitor)', async () => {
    await allow('owner', 'owner');
    const r = await call('owner', 'google.com', request('eggs'), NO_TOKEN);
    assert.equal(r.ok, true);
    assert.equal(r.tier, 'owner');
  });
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

describe('the pool at the real DeepSeek ceiling (T-18 M6: the stop at about $0.24)', () => {
  // The model the function uses outside the emulator. Its ceiling is the
  // reservation per call: 2 attempts x (70,000 in x $0.30 + 8,000 out x $1.20)
  // at peak prices. A change to the token bounds, attempts or prices moves
  // these numbers, and this test with them.
  const real = MODELS['deepseek-flash'];
  const REAL_CEILING = ceilingMicros(real);
  const LAST_ADMITTED = BUDGET - REAL_CEILING; // $0.2388 of settled spend
  const reserveReal = (uid: string) => reserve(db(), uid, 'demo', TIERS.demo, real, new Date());
  const refusedWith = async (uid: string) => {
    try {
      await reserveReal(uid);
      return 'ok';
    } catch (error) {
      return reasonOf(error);
    }
  };

  test('the ceiling is $0.0612, so new calls stop once settled spend passes $0.2388', async () => {
    assert.equal(REAL_CEILING, 61_200);
    assert.equal(LAST_ADMITTED, 238_800);
    await poolDoc().set({ spentMicros: LAST_ADMITTED, reservedMicros: 0 });
    assert.equal(await refusedWith('a'), 'ok');
    await poolDoc().set({ spentMicros: LAST_ADMITTED + 1, reservedMicros: 0 });
    assert.equal(await refusedWith('b'), 'globalBudget');
  });

  test('from an empty pool at most 4 calls are in flight at once; settled, spend stays far under $0.30', async () => {
    const results = await Promise.allSettled(Array.from({ length: 20 }, (_, i) => reserveReal(`v${i}`)));
    const ok = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []));
    assert.equal(ok.length, 4);
    assert.ok(results.every((r) => r.status === 'fulfilled' || reasonOf(r.reason) === 'globalBudget'));
    assert.equal((await poolDoc().get()).get('reservedMicros'), 4 * REAL_CEILING);
    // Each settles at a cold demo call's real cost at peak (T-19's eval: about $0.0039).
    await Promise.all(ok.map((r) => settle(db(), r, 3_900, new Date())));
    const pool = await poolDoc().get();
    assert.deepEqual([pool.get('spentMicros'), pool.get('reservedMicros')], [4 * 3_900, 0]);
  });

  test('calls one after another stop at about $0.24 and never pass $0.30', async () => {
    let served = 0;
    for (let i = 0; i < 100; i++) {
      let reservation;
      try {
        reservation = await reserveReal(`s${i}`);
      } catch (error) {
        assert.equal(reasonOf(error), 'globalBudget');
        break;
      }
      await settle(db(), reservation, 3_900, new Date());
      served++;
    }
    const spent = (await poolDoc().get()).get('spentMicros');
    // 62 calls of $0.0039: the 62nd is admitted at $0.2379 of spend, the 63rd refused at $0.2418.
    assert.equal(served, 62);
    assert.ok(spent > LAST_ADMITTED && spent <= LAST_ADMITTED + 3_900, `spent ${spent}`);
    assert.ok(spent <= BUDGET);
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
