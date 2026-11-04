// The reservation's lifecycle when something around the provider fails (M7 of
// the Codex review). No network, no emulator: a stub Firestore that records
// the counter writes and fails on command.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { FieldValue, type Firestore } from 'firebase-admin/firestore';

import { COLLECTIONS, MODELS, TIERS, ceilingMicros, type TierLimits } from '../src/config';
import { handleAiCommand, type Deps } from '../src/handler';
import type { RequestMeta } from '../src/log';
import { ProviderError, type AiProvider } from '../src/provider/types';

const model = MODELS.fake;
const usage = { inputTokens: 10, outputTokens: 5, cacheReadTokens: 0, cacheWriteTokens: 0 };

// A tier with a pool, so a settlement moves money there too; the owner has none (Q-63).
const LIMITED: TierLimits = { ...TIERS.owner, requestsPerDay: 100, pools: ['global'] };

function setup(options: { failPromptLog?: boolean; failSettle?: boolean; provider?: AiProvider['call']; limits?: TierLimits }) {
  const counters = {
    reserved: 0,
    /** Each committed settlement's writes. */
    settled: [] as Record<string, Record<string, unknown>>[],
    providerCalls: 0,
  };
  const snapshot = { get: (key: string) => (key === 'tier' ? 'owner' : 0) };
  const db = {
    collection: (name: string) => ({
      doc: () => ({
        name,
        get: async () => snapshot,
        set: async () => {
          if (name === COLLECTIONS.promptLog && options.failPromptLog === true) throw new Error('prompt log down');
        },
      }),
    }),
    runTransaction: async (body: (tx: unknown) => Promise<unknown>) => {
      counters.reserved++;
      return body({ get: async () => snapshot, set: () => {} });
    },
    batch: () => {
      const writes: Record<string, Record<string, unknown>> = {};
      return {
        set: (ref: { name: string }, data: Record<string, unknown>) => {
          writes[ref.name] = data;
        },
        commit: async () => {
          if (options.failSettle === true) throw new Error('counters down');
          counters.settled.push(writes);
        },
      };
    },
  };
  const logged: RequestMeta[] = [];
  const provider: AiProvider = {
    name: 'stub',
    call: async (call) => {
      counters.providerCalls++;
      if (options.provider !== undefined) return options.provider(call);
      return { content: [{ type: 'tool_call', id: 'c1', name: 'reply', args: { text: 'hi' } }], usage, stopReason: 'end' };
    },
  };
  const deps: Deps = {
    db: db as unknown as Firestore,
    provider,
    model,
    limits: options.limits ?? LIMITED,
    log: (_, entry) => logged.push(entry),
    now: () => new Date('2026-11-04T12:00:00Z'),
    newRequestId: () => 'request-id',
  };
  return { deps, counters, logged };
}

const input = {
  uid: 'user',
  appCheckTokenPresent: false,
  data: { prompt: 'milk', locale: 'en', platform: 'android', lists: [], openList: null },
};

/** Exactly one settlement: the whole ceiling back from reserved, [spent] added to both counters. */
function assertSettled(settled: Record<string, Record<string, unknown>>[], spent: number): void {
  assert.equal(settled.length, 1);
  const pool = settled[0][COLLECTIONS.poolUsage];
  const user = settled[0][COLLECTIONS.userUsage];
  assert.ok((pool.reservedMicros as FieldValue).isEqual(FieldValue.increment(-ceilingMicros(model))), 'reserved');
  assert.ok((pool.spentMicros as FieldValue).isEqual(FieldValue.increment(spent)), 'pool spent');
  assert.ok((user.spentMicros as FieldValue).isEqual(FieldValue.increment(spent)), 'user spent');
}

describe('the reservation', () => {
  test('a prompt-log failure releases it and no provider runs', async () => {
    const { deps, counters } = setup({ failPromptLog: true });
    await assert.rejects(handleAiCommand(input, deps));
    assert.equal(counters.reserved, 1);
    assert.equal(counters.providerCalls, 0);
    assertSettled(counters.settled, 0);
  });

  test('an answer settles its real cost, once', async () => {
    const { deps, counters, logged } = setup({});
    const result = await handleAiCommand(input, deps);
    assert.equal(result.outcome, 'ok');
    assert.ok(typeof logged[0].costMicros === 'number');
    assertSettled(counters.settled, logged[0].costMicros as number);
    assert.ok((logged[0].costMicros as number) < ceilingMicros(model));
  });

  test('with no pool, as the owner, only the user is settled (Q-63)', async () => {
    const { deps, counters, logged } = setup({ limits: TIERS.owner });
    await handleAiCommand(input, deps);
    assert.equal(counters.settled.length, 1);
    assert.deepEqual(Object.keys(counters.settled[0]), [COLLECTIONS.userUsage]);
    assert.ok(
      (counters.settled[0][COLLECTIONS.userUsage].spentMicros as FieldValue).isEqual(
        FieldValue.increment(logged[0].costMicros as number),
      ),
    );
  });

  test('an unbilled provider error settles at zero, once', async () => {
    const { deps, counters } = setup({
      provider: async () => {
        throw new ProviderError('billing', 402);
      },
    });
    await assert.rejects(handleAiCommand(input, deps));
    assertSettled(counters.settled, 0);
  });

  test('a possibly billed provider error keeps the ceiling, once', async () => {
    const { deps, counters } = setup({
      provider: async () => {
        throw new ProviderError('network');
      },
    });
    await assert.rejects(handleAiCommand(input, deps));
    assertSettled(counters.settled, ceilingMicros(model));
  });

  test('a settlement failure after an answer still returns it, and the log says so', async () => {
    const { deps, logged } = setup({ failSettle: true });
    const result = await handleAiCommand(input, deps);
    assert.equal(result.outcome, 'ok');
    assert.equal(result.toolCalls[0].name, 'reply');
    assert.equal(logged[0].settleFailed, true);
  });

  test("a settlement failure does not hide the provider's failure", async () => {
    const { deps, logged } = setup({
      failSettle: true,
      provider: async () => {
        throw new ProviderError('billing', 402);
      },
    });
    await assert.rejects(handleAiCommand(input, deps), (error: { details?: { reason?: string; kind?: string } }) => {
      assert.equal(error.details?.reason, 'provider');
      assert.equal(error.details?.kind, 'billing');
      return true;
    });
    assert.equal(logged[0].settleFailed, true);
  });
});
