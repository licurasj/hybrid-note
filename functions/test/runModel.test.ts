// runModel's deadline, its one retry of busy answers and the fallback when
// the self-correction call fails (M2 and M3 of the T-19 unit 5 review).
// No network, no emulator: a scripted provider and a fake clock.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { MODELS } from '../src/config';
import { CALL_TIMEOUT_MS, MIN_ATTEMPT_MS, PROVIDER_DEADLINE_MS, runCost, runModel, unbilled, usageReadable } from '../src/handler';
import { structuralCheck, type SchemaCheck } from '../src/output';
import { ProviderError, type AiProvider, type ProviderCall, type ProviderResponse } from '../src/provider/types';
import type { AiRequest } from '../src/request';

const request: AiRequest = { prompt: 'eggs', locale: 'en', lists: [{ id: 'g', name: 'Grocery', fields: [], aiAllowed: true }], openList: null };
const usage = { inputTokens: 10, outputTokens: 5, cacheReadTokens: 0, cacheWriteTokens: 0 };
const ok: ProviderResponse = {
  content: [{ type: 'tool_call', id: 'c1', name: 'reply', args: { text: 'hi' } }],
  usage,
  stopReason: 'end',
};

/** A provider answering from a script; each step may advance the fake clock. */
function scripted(steps: (ProviderResponse | Error)[], clock: { now: number }, advance = 0) {
  const calls: ProviderCall[] = [];
  const provider: AiProvider = {
    name: 'scripted',
    call: async (input) => {
      calls.push(input);
      clock.now += advance;
      const step = steps.shift();
      if (step === undefined) throw new Error('script ended');
      if (step instanceof Error) throw step;
      return step;
    },
  };
  return { provider, calls };
}

const failOnce = (): SchemaCheck => {
  let first = true;
  return () => (first ? ((first = false), ['bad']) : []);
};

function run(provider: AiProvider, check: SchemaCheck, clock: { now: number }) {
  return runModel(provider, MODELS.fake, request, check, new Date(), { clock: () => clock.now, wait: async () => {} });
}

describe('runModel', () => {
  test('each call gets the time left, at most CALL_TIMEOUT_MS', async () => {
    const clock = { now: 0 };
    const { provider, calls } = scripted([ok, ok], clock, 60_000);
    const result = await run(provider, failOnce(), clock);
    assert.equal(result.attempts, 2);
    assert.equal(calls[0].timeoutMs, CALL_TIMEOUT_MS);
    assert.equal(calls[1].timeoutMs, PROVIDER_DEADLINE_MS - 60_000);
  });

  test('a busy answer is retried once; a second one fails the request', async () => {
    const clock = { now: 0 };
    const busy = () => new ProviderError('overloaded', 529);
    const once = scripted([busy(), ok], clock);
    assert.equal((await run(once.provider, structuralCheck, clock)).response, ok);
    assert.equal(once.calls.length, 2);
    const twice = scripted([new ProviderError('rateLimit', 429), new ProviderError('rateLimit', 429)], clock);
    await assert.rejects(run(twice.provider, structuralCheck, clock), (e: ProviderError) => e.kind === 'rateLimit');
    assert.equal(twice.calls.length, 2);
  });

  test('errors that may have been billed, or are final, are not retried', async () => {
    for (const error of [new ProviderError('network'), new ProviderError('badRequest', 400), new ProviderError('billing', 402), new ProviderError('overloaded')]) {
      const clock = { now: 0 };
      const { provider, calls } = scripted([error, ok], clock);
      await assert.rejects(run(provider, structuralCheck, clock));
      assert.equal(calls.length, 1, error.message);
    }
  });

  test('no busy retry when too little time is left', async () => {
    const clock = { now: 0 };
    const { provider, calls } = scripted([new ProviderError('overloaded', 503), ok], clock, PROVIDER_DEADLINE_MS - MIN_ATTEMPT_MS);
    await assert.rejects(run(provider, structuralCheck, clock));
    assert.equal(calls.length, 1);
  });

  test('the self-correction is skipped when too little time is left; the first answer is used', async () => {
    const clock = { now: 0 };
    const { provider, calls } = scripted([ok, ok], clock, PROVIDER_DEADLINE_MS - MIN_ATTEMPT_MS + 1);
    const result = await run(provider, failOnce(), clock);
    assert.equal(calls.length, 1);
    assert.equal(result.response, ok);
    assert.equal(result.retryError, 'noTime');
  });

  test('a failed self-correction falls back to the first answer and says whether it may be billed', async () => {
    for (const [error, billed] of [
      [new ProviderError('network'), true],
      [new ProviderError('badRequest', 400), false],
    ] as const) {
      const clock = { now: 0 };
      const { provider } = scripted([ok, error], clock);
      const result = await run(provider, failOnce(), clock);
      assert.equal(result.response, ok);
      assert.deepEqual(result.usage, usage);
      assert.equal(result.attempts, 2);
      assert.equal(result.retryError, error.kind);
      assert.equal(result.retryMaybeBilled, billed);
    }
  });

  test('a cut, refused or narrower second answer leaves the first in place (L14)', async () => {
    const two: ProviderResponse = {
      content: [
        { type: 'tool_call', id: 'a', name: 'reply', args: { text: 'a' } },
        { type: 'tool_call', id: 'b', name: 'decline', args: { reason: 'offTopic' } },
      ],
      usage,
      stopReason: 'end',
    };
    // The check rejects call b of the first answer only.
    const onlyB = (): SchemaCheck => {
      let first = true;
      return (name) => (first && name === 'decline' ? ((first = false), ['bad']) : []);
    };
    const cases: [ProviderResponse, string | undefined][] = [
      [{ ...ok, stopReason: 'length' }, 'length'],
      [{ ...ok, stopReason: 'refusal' }, 'refusal'],
      [{ ...ok, content: [] }, 'fewerCalls'],
      [ok, undefined], // one valid call, as many as the first answer had
    ];
    for (const [second, flaw] of cases) {
      const clock = { now: 0 };
      const { provider } = scripted([two, second], clock);
      const result = await run(provider, onlyB(), clock);
      assert.equal(result.attempts, 2);
      assert.equal(result.retryError, flaw);
      assert.equal(result.response, flaw === undefined ? second : two);
      assert.deepEqual(result.usage, { inputTokens: 20, outputTokens: 10, cacheReadTokens: 0, cacheWriteTokens: 0 });
    }
  });

  test('gateway timeouts (504, 524) count as possibly billed and are not retried (L15)', async () => {
    for (const status of [504, 524]) {
      assert.ok(!unbilled(new ProviderError('overloaded', status)));
      const clock = { now: 0 };
      const { provider, calls } = scripted([new ProviderError('overloaded', status), ok], clock);
      await assert.rejects(run(provider, structuralCheck, clock));
      assert.equal(calls.length, 1);
    }
  });

  test('unbilled: error answers yes, timeouts and unknown errors no', () => {
    assert.ok(unbilled(new ProviderError('auth', 401)));
    assert.ok(unbilled(new ProviderError('billing', 402)));
    assert.ok(unbilled(new ProviderError('rateLimit', 429)));
    assert.ok(unbilled(new ProviderError('overloaded', 503)));
    assert.ok(!unbilled(new ProviderError('overloaded')));
    assert.ok(!unbilled(new ProviderError('network')));
    assert.ok(!unbilled(new ProviderError('badResponse', 200)));
    assert.ok(!unbilled(new Error('x')));
  });
});

describe('runModel, T-19 unit 6', () => {
  test('time already used by the request comes off the deadline (N6)', async () => {
    const clock = { now: 0 };
    const { provider, calls } = scripted([ok], clock);
    await runModel(provider, MODELS.fake, request, structuralCheck, new Date(), {
      clock: () => clock.now,
      wait: async () => {},
      elapsedMs: 70_000,
    });
    assert.equal(calls[0].timeoutMs, PROVIDER_DEADLINE_MS - 70_000);
  });

  test('a busy retry is reported (N8)', async () => {
    const clock = { now: 0 };
    const { provider } = scripted([new ProviderError('rateLimit', 429), ok], clock);
    let busy = 0;
    await runModel(provider, MODELS.fake, request, structuralCheck, new Date(), {
      clock: () => clock.now,
      wait: async () => {},
      onBusyRetry: () => busy++,
    });
    assert.equal(busy, 1);
  });

  test('an item call naming an unknown list gets the self-correction (L3)', async () => {
    const clock = { now: 0 };
    const wrong: ProviderResponse = {
      content: [{ type: 'tool_call', id: 'c1', name: 'upsert_items', args: { listId: 'nope', items: [] } }],
      usage,
      stopReason: 'end',
    };
    const right: ProviderResponse = {
      content: [{ type: 'tool_call', id: 'c2', name: 'upsert_items', args: { listId: 'g', items: [] } }],
      usage,
      stopReason: 'end',
    };
    const { provider, calls } = scripted([wrong, right], clock);
    const result = await run(provider, structuralCheck, clock);
    assert.equal(result.attempts, 2);
    assert.equal(result.response, right);
    assert.match(calls[1].retry!.feedback[0].errors[0], /listId/);
  });
});

describe('runCost', () => {
  const deepseek = MODELS['deepseek-flash'];
  const ceiling = 45_600;

  test('unreadable usage costs the ceiling (L1)', () => {
    const at = new Date('2026-11-03T12:00:00Z');
    for (const bad of [
      { ...usage, inputTokens: NaN },
      { ...usage, inputTokens: -5 },
      { ...usage, outputTokens: Infinity },
      { ...usage, cacheReadTokens: undefined as unknown as number },
    ]) {
      assert.ok(!usageReadable(bad));
      assert.equal(runCost(deepseek, bad, at, at, ceiling), ceiling);
    }
    assert.ok(usageReadable(usage));
  });

  test('a request that crosses into peak hours is priced at peak (N1)', () => {
    const big = { inputTokens: 10_000, outputTokens: 1_000, cacheReadTokens: 0, cacheWriteTokens: 0 };
    // Tuesday 00:59:30 UTC off-peak, 01:00:30 peak.
    const start = new Date('2026-11-03T00:59:30Z');
    const end = new Date('2026-11-03T01:00:30Z');
    assert.equal(runCost(deepseek, big, start, end, ceiling), runCost(deepseek, big, end, end, ceiling));
    assert.ok(runCost(deepseek, big, start, end, ceiling) > runCost(deepseek, big, start, start, ceiling));
  });
});
