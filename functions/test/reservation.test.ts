// The reservation's lifecycle when something around the provider fails (M7 of
// the Codex review). No network, no emulator: a stub Firestore that records
// the counter writes and fails on command.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import type { Firestore } from 'firebase-admin/firestore';

import { COLLECTIONS, MODELS } from '../src/config';
import { handleAiCommand, type Deps } from '../src/handler';
import type { RequestMeta } from '../src/log';
import { ProviderError, type AiProvider } from '../src/provider/types';

const model = MODELS.fake;
const usage = { inputTokens: 10, outputTokens: 5, cacheReadTokens: 0, cacheWriteTokens: 0 };

function setup(options: { failPromptLog?: boolean; failSettle?: boolean; provider?: AiProvider['call'] }) {
  const counters = { reserved: 0, settled: [] as unknown[], providerCalls: 0 };
  const snapshot = { get: (key: string) => (key === 'tier' ? 'owner' : 0) };
  const db = {
    collection: (name: string) => ({
      doc: () => ({
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
    batch: () => ({
      set: () => {},
      commit: async () => {
        if (options.failSettle === true) throw new Error('counters down');
        counters.settled.push('settled');
      },
    }),
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

describe('the reservation', () => {
  test('a prompt-log failure releases it and no provider runs', async () => {
    const { deps, counters } = setup({ failPromptLog: true });
    await assert.rejects(handleAiCommand(input, deps));
    assert.equal(counters.reserved, 1);
    assert.equal(counters.providerCalls, 0);
    assert.equal(counters.settled.length, 1);
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
