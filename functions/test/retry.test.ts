// The schema self-correction round and the length cut (T-19 unit 3, Q-34 A):
// handleAiCommand with the fake provider against the Firestore emulator.
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { HttpsError } from 'firebase-functions/v2/https';

import { COLLECTIONS, MAX_ATTEMPTS, MODELS, ceilingMicros, costMicros } from '../src/config';
import { handleAiCommand, type AiResponse } from '../src/handler';
import type { RequestMeta } from '../src/log';
import { FakeProvider } from '../src/provider/fake';
import type { AiProvider, ProviderCall } from '../src/provider/types';
import { allow, clearFirestore, db, today } from './helpers';

const UID = 'retry-test-uid';
const model = MODELS.fake;

function data(prompt: string) {
  return {
    prompt,
    platform: 'android',
    locale: 'en',
    lists: [{ id: 'grocery', name: 'Grocery', fields: [] }],
    openList: { definition: { id: 'grocery', aiAllowed: true, fields: [] }, items: [] },
  };
}

/** The fake provider, recording every call it gets. */
function recording() {
  const calls: ProviderCall[] = [];
  const fake = new FakeProvider();
  const provider: AiProvider = { name: 'fake', call: (input) => (calls.push(input), fake.call(input)) };
  return { provider, calls };
}

async function run(prompt: string, provider: AiProvider) {
  const entries: RequestMeta[] = [];
  let result: AiResponse | undefined;
  let error: unknown;
  try {
    result = await handleAiCommand(
      { uid: UID, appCheckTokenPresent: false, data: data(prompt) },
      { db: db(), provider, model, log: (_, e) => entries.push(e), now: () => new Date(), newRequestId: () => 'r1' },
    );
  } catch (e) {
    error = e;
  }
  return { result, error, entry: entries[0] };
}

async function spentMicros(): Promise<number> {
  const pool = await db().collection(COLLECTIONS.poolUsage).doc(`global_${today()}`).get();
  return pool.get('spentMicros') as number;
}

beforeEach(async () => {
  await clearFirestore();
  await allow(UID);
});

describe('schema self-correction', () => {
  test('a valid first answer makes one call', async () => {
    const { provider, calls } = recording();
    const { result, entry } = await run('eggs', provider);
    assert.equal(calls.length, 1);
    assert.equal(result?.outcome, 'ok');
    assert.equal(entry.attempts, 1);
  });

  test('a schema failure gets one retry with the errors, and the corrected answer is used', async () => {
    const { provider, calls } = recording();
    const { result, entry } = await run('[fake:badschema] eggs, milk', provider);
    assert.equal(calls.length, 2);
    const feedback = calls[1].retry!.feedback;
    assert.equal(feedback.length, 1);
    assert.ok(feedback[0].errors.some((e) => e.startsWith('/items/0/values')));
    assert.equal(result?.outcome, 'ok');
    assert.equal(result?.toolCalls[0].name, 'upsert_items');
    assert.equal(entry.attempts, 2);
    // Both calls are paid for, and settled.
    const one = (await new FakeProvider().call(calls[0])).usage;
    const two = { ...one, inputTokens: 2 * one.inputTokens, outputTokens: 2 * one.outputTokens };
    assert.equal(result?.usage.inputTokens, two.inputTokens);
    assert.equal(await spentMicros(), costMicros(model, two, new Date()));
  });

  test('a second failure is not retried again; the bad call is dropped', async () => {
    const { provider, calls } = recording();
    const { result } = await run('[fake:badtwice] eggs', provider);
    assert.equal(calls.length, 2);
    assert.equal(result?.outcome, 'declined');
    assert.equal(result?.declineReason, 'noValidTool');
  });

  test('unknown tools are dropped, not retried', async () => {
    const provider: AiProvider = {
      name: 'fake',
      call: async () => ({
        content: [{ type: 'tool_call', id: 'x', name: 'delete_list', args: { listId: 'grocery' } }],
        usage: { inputTokens: 10, outputTokens: 10, cacheReadTokens: 0, cacheWriteTokens: 0 },
        stopReason: 'end',
      }),
    };
    const { result, entry } = await run('delete it', provider);
    assert.equal(entry.attempts, 1);
    assert.equal(result?.declineReason, 'noValidTool');
  });
});

describe('provider failures (M1, M3 of the unit 5 review)', () => {
  async function reservedMicros(): Promise<number> {
    const pool = await db().collection(COLLECTIONS.poolUsage).doc(`global_${today()}`).get();
    return pool.get('reservedMicros') as number;
  }

  test('an error answer that cannot have been billed settles to $0', async () => {
    const { error, entry } = await run('[fake:billing] eggs', new FakeProvider());
    assert.ok(error instanceof HttpsError);
    assert.deepEqual(error.details, { reason: 'provider' });
    assert.equal(entry.providerError, 'billing');
    assert.equal(await spentMicros(), 0);
    assert.equal(await reservedMicros(), 0);
  });

  test('an error that may have been billed keeps the ceiling spent', async () => {
    const { error } = await run('[fake:fail] eggs', new FakeProvider());
    assert.ok(error instanceof HttpsError);
    assert.equal(await spentMicros(), ceilingMicros(model));
  });

  test('a failed self-correction keeps the first answer and counts the failed call at its ceiling', async () => {
    const { provider, calls } = recording();
    const { result, entry } = await run('[fake:retryfail] eggs', provider);
    assert.equal(calls.length, 2);
    assert.equal(entry.retryError, 'network');
    // The first answer's only call broke the schema, so it is dropped.
    assert.equal(result?.declineReason, 'noValidTool');
    const first = (await new FakeProvider().call(calls[0])).usage;
    const expected = costMicros(model, first, new Date()) + Math.ceil(ceilingMicros(model) / MAX_ATTEMPTS);
    assert.equal(await spentMicros(), expected);
    assert.equal(Math.round((result?.usage.costUsd ?? 0) * 1e6), expected);
  });
});

describe('length cut', () => {
  test('a cut answer is refused as outputTooLong and its real cost is settled', async () => {
    const { provider, calls } = recording();
    const { error, entry } = await run('[fake:length] eggs', provider);
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, 'resource-exhausted');
    assert.deepEqual(error.details, { reason: 'outputTooLong' });
    assert.equal(calls.length, 1, 'no retry for a cut answer');
    assert.equal(entry.stopReason, 'length');
    assert.equal(await spentMicros(), entry.costMicros);
  });
});
