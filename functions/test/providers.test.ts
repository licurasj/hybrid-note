// The Claude, DeepSeek and OpenAI adapters against stubbed clients: request shape,
// answer mapping, the retry turn and typed errors (T-19 unit 3). No network,
// no keys: real calls happen only in the owner-approved eval (eval/run.ts).
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import Anthropic from '@anthropic-ai/sdk';
import OpenAI from 'openai';

import { MODELS } from '../src/config';
import { ClaudeProvider, mapError } from '../src/provider/claude';
import { DEEPSEEK_URL, DeepSeekProvider, type Fetch } from '../src/provider/deepseek';
import { OpenAiProvider, failedError, mapError as openaiMapError } from '../src/provider/openai';
import { ProviderError, type ProviderCall } from '../src/provider/types';
import { loadTools } from '../src/schemas';

function input(model: string, extra: Partial<ProviderCall> = {}): ProviderCall {
  const config = MODELS[model];
  return {
    model: config,
    system: 'SYSTEM',
    tools: loadTools(config.strictTools),
    user: 'USER',
    request: { prompt: 'p', locale: 'en', lists: [], openList: null },
    ...extra,
  };
}

/** A stand-in for the SDK client that records the request and returns `reply`. */
const claudeOptions: unknown[] = [];

function claudeStub(reply: unknown | (() => never)) {
  const sent: Record<string, unknown>[] = [];
  const client = {
    messages: {
      create: async (params: Record<string, unknown>, options?: unknown) => {
        sent.push(params);
        claudeOptions.push(options);
        if (typeof reply === 'function') return (reply as () => never)();
        return reply;
      },
    },
  } as unknown as Anthropic;
  return { provider: new ClaudeProvider(undefined, client), sent };
}

const claudeMessage = (content: unknown[], stop_reason = 'tool_use') => ({
  id: 'msg_1',
  type: 'message',
  role: 'assistant',
  model: 'claude-haiku-5-5',
  content,
  stop_reason,
  stop_details: null,
  usage: { input_tokens: 300, output_tokens: 90, cache_read_input_tokens: 9000, cache_creation_input_tokens: 0 },
});

describe('ClaudeProvider', () => {
  test('sends tools and system as one cached prefix, strict tools, tool_choice auto, effort, no sampling', async () => {
    const { provider, sent } = claudeStub(claudeMessage([]));
    await provider.call(input('claude-haiku-5-5'));
    const params = sent[0];
    assert.equal(params.model, 'claude-haiku-5-5');
    assert.equal(params.max_tokens, 8000);
    assert.deepEqual(params.system, [{ type: 'text', text: 'SYSTEM', cache_control: { type: 'ephemeral' } }]);
    assert.deepEqual(params.tool_choice, { type: 'auto' });
    assert.deepEqual(params.output_config, { effort: 'medium' });
    const tools = params.tools as { name: string; strict?: boolean; input_schema: unknown }[];
    assert.equal(tools.length, 8);
    assert.ok(tools.every((t) => typeof t.input_schema === 'object'));
    // The two large tools go without strict: Claude refuses the grammar of all seven.
    assert.deepEqual(tools.filter((t) => t.strict === true).map((t) => t.name), ['upsert_items', 'delete_items', 'choose_list', 'reply', 'decline']);
    assert.deepEqual(params.messages, [{ role: 'user', content: 'USER' }]);
    for (const key of ['temperature', 'top_p', 'top_k', 'thinking']) assert.ok(!(key in params), key);
    assert.deepEqual(claudeOptions.at(-1), { timeout: 50_000 });
    await provider.call(input('claude-haiku-5-5', { timeoutMs: 12_345 }));
    assert.deepEqual(claudeOptions.at(-1), { timeout: 12_345 });
  });

  test('maps thinking, text and tool_use blocks, usage and stop reasons', async () => {
    const { provider } = claudeStub(
      claudeMessage([
        { type: 'thinking', thinking: '', signature: 's' },
        { type: 'text', text: 'Adding.' },
        { type: 'tool_use', id: 'tu1', name: 'upsert_items', input: { listId: 'g', items: [] } },
      ]),
    );
    const response = await provider.call(input('claude-haiku-5-5'));
    assert.deepEqual(response.content, [
      { type: 'text', text: 'Adding.' },
      { type: 'tool_call', id: 'tu1', name: 'upsert_items', args: { listId: 'g', items: [] } },
    ]);
    assert.deepEqual(response.usage, { inputTokens: 300, outputTokens: 90, cacheReadTokens: 9000, cacheWriteTokens: 0 });
    assert.equal(response.stopReason, 'end');
    assert.equal((response.raw as unknown[]).length, 3);

    for (const [reason, mapped] of [
      ['end_turn', 'end'],
      ['refusal', 'refusal'],
      ['max_tokens', 'length'],
      ['model_context_window_exceeded', 'length'],
    ] as const) {
      const r = await claudeStub(claudeMessage([], reason)).provider.call(input('claude-haiku-5-5'));
      assert.equal(r.stopReason, mapped, reason);
    }
  });

  test('the retry sends the answer back unchanged with a tool_result for every tool_use', async () => {
    const first = claudeMessage([
      { type: 'thinking', thinking: '', signature: 's' },
      { type: 'tool_use', id: 'ok1', name: 'reply', input: { text: 'hi' } },
      { type: 'tool_use', id: 'bad1', name: 'upsert_items', input: { listId: 'g', items: [{ values: {} }] } },
    ]);
    const { provider, sent } = claudeStub(first);
    const previous = await provider.call(input('claude-haiku-5-5'));
    await provider.call(input('claude-haiku-5-5', { retry: { previous, feedback: [{ id: 'bad1', errors: ['/items/0/values: must be array'] }] } }));
    const messages = sent[1].messages as { role: string; content: unknown }[];
    assert.equal(messages.length, 3);
    assert.deepEqual(messages[1], { role: 'assistant', content: first.content });
    const results = messages[2].content as Record<string, unknown>[];
    assert.equal(results[0].tool_use_id, 'ok1');
    assert.equal(results[0].is_error, undefined);
    assert.equal(results[1].tool_use_id, 'bad1');
    assert.equal(results[1].is_error, true);
    assert.match(String(results[1].content), /must be array/);
    assert.equal(results[2].type, 'text');
  });

  test('typed SDK errors become ProviderError kinds', () => {
    const headers = new Headers();
    const cases: [unknown, string][] = [
      [Anthropic.APIError.generate(401, { error: { type: 'authentication_error' } }, 'x', headers), 'auth'],
      [Anthropic.APIError.generate(400, { error: { type: 'billing_error' } }, 'x', headers), 'billing'],
      [Anthropic.APIError.generate(429, { error: { type: 'rate_limit_error' } }, 'x', headers), 'rateLimit'],
      [Anthropic.APIError.generate(529, { error: { type: 'overloaded_error' } }, 'x', headers), 'overloaded'],
      [Anthropic.APIError.generate(400, { error: { type: 'invalid_request_error' } }, 'x', headers), 'badRequest'],
      [new Anthropic.APIConnectionTimeoutError(), 'network'],
      [new Error('something else'), 'badResponse'],
    ];
    for (const [error, kind] of cases) assert.equal(mapError(error).kind, kind);
  });

  test('a provider message never reaches the error text', async () => {
    const { provider } = claudeStub(() => {
      throw Anthropic.APIError.generate(400, { error: { type: 'invalid_request_error' } }, 'echo PROMPT-TEXT', new Headers());
    });
    await assert.rejects(provider.call(input('claude-haiku-5-5')), (e: Error) => {
      assert.ok(e instanceof ProviderError && !e.message.includes('PROMPT-TEXT'));
      return true;
    });
  });

  test('without a key there is no provider', () => {
    assert.throws(() => new ClaudeProvider(''), (e: ProviderError) => e.kind === 'noKey');
  });
});

/** A fetch stand-in answering with the given responses in turn. */
function fetchStub(...answers: (Response | Error)[]) {
  const sent: { url: string; init: RequestInit }[] = [];
  const fetchFn: Fetch = async (url, init) => {
    sent.push({ url, init });
    const next = answers.shift();
    if (next === undefined) throw new Error('no more answers');
    if (next instanceof Error) throw next;
    return next;
  };
  return { fetchFn, sent };
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const completion = (message: Record<string, unknown>, finish_reason = 'tool_calls') => ({
  choices: [{ index: 0, message: { role: 'assistant', content: null, ...message }, finish_reason }],
  usage: { prompt_tokens: 10000, prompt_cache_hit_tokens: 9000, prompt_cache_miss_tokens: 1000, completion_tokens: 200 },
});

describe('DeepSeekProvider', () => {
  test('sends the OpenAI-format request with function tools, tool_choice auto and reasoning_effort', async () => {
    const { fetchFn, sent } = fetchStub(json(completion({ content: 'x' }, 'stop')));
    await new DeepSeekProvider('KEY', fetchFn).call(input('deepseek-flash'));
    assert.equal(sent[0].url, DEEPSEEK_URL);
    assert.equal((sent[0].init.headers as Record<string, string>).Authorization, 'Bearer KEY');
    const body = JSON.parse(String(sent[0].init.body));
    assert.equal(body.model, 'deepseek-flash');
    assert.equal(body.max_tokens, 8000);
    assert.equal(body.tool_choice, 'auto');
    assert.equal(body.reasoning_effort, 'high');
    assert.equal(body.stream, false);
    assert.deepEqual(body.messages, [
      { role: 'system', content: 'SYSTEM' },
      { role: 'user', content: 'USER' },
    ]);
    assert.equal(body.tools.length, 8);
    assert.equal(body.tools[0].type, 'function');
    assert.deepEqual(Object.keys(body.tools[0].function), ['name', 'description', 'parameters']);
    assert.equal(body.tools[0].function.strict, undefined);
  });

  test('maps tool calls (bad JSON to undefined args), cache usage and finish reasons', async () => {
    const { fetchFn } = fetchStub(
      json(
        completion({
          content: '  ',
          reasoning_content: 'thinking',
          tool_calls: [
            { id: 'c1', type: 'function', function: { name: 'reply', arguments: '{"text":"hi"}' } },
            { id: 'c2', type: 'function', function: { name: 'reply', arguments: '{"text":' } },
          ],
        }),
      ),
    );
    const response = await new DeepSeekProvider('KEY', fetchFn).call(input('deepseek-flash'));
    assert.deepEqual(response.content, [
      { type: 'tool_call', id: 'c1', name: 'reply', args: { text: 'hi' } },
      { type: 'tool_call', id: 'c2', name: 'reply', args: undefined },
    ]);
    assert.deepEqual(response.usage, { inputTokens: 1000, outputTokens: 200, cacheReadTokens: 9000, cacheWriteTokens: 0 });
    for (const [reason, mapped] of [
      ['stop', 'end'],
      ['tool_calls', 'end'],
      ['length', 'length'],
      ['content_filter', 'refusal'],
    ] as const) {
      const r = await new DeepSeekProvider('KEY', fetchStub(json(completion({}, reason))).fetchFn).call(input('deepseek-flash'));
      assert.equal(r.stopReason, mapped, reason);
    }
    await assert.rejects(
      new DeepSeekProvider('KEY', fetchStub(json(completion({}, 'insufficient_system_resource'))).fetchFn).call(input('deepseek-flash')),
      (e: ProviderError) => e.kind === 'overloaded',
    );
  });

  test('the retry sends the assistant turn back with a tool message per call', async () => {
    const message = {
      content: null,
      reasoning_content: 'r',
      tool_calls: [
        { id: 'ok1', type: 'function', function: { name: 'reply', arguments: '{"text":"hi"}' } },
        { id: 'bad1', type: 'function', function: { name: 'decline', arguments: '{"reason":"x"}' } },
      ],
    };
    const { fetchFn, sent } = fetchStub(json(completion(message)), json(completion({ content: 'x' }, 'stop')));
    const provider = new DeepSeekProvider('KEY', fetchFn);
    const previous = await provider.call(input('deepseek-flash'));
    await provider.call(input('deepseek-flash', { retry: { previous, feedback: [{ id: 'bad1', errors: ['/reason: must be equal to one of the allowed values'] }] } }));
    const messages = JSON.parse(String(sent[1].init.body)).messages;
    assert.equal(messages.length, 6);
    assert.deepEqual(messages[2], { role: 'assistant', ...message });
    assert.equal(messages[3].role, 'tool');
    assert.equal(messages[3].tool_call_id, 'ok1');
    assert.equal(messages[4].tool_call_id, 'bad1');
    assert.match(messages[4].content, /allowed values/);
    assert.equal(messages[5].role, 'user');
  });

  test('HTTP errors map to kinds in one attempt (retries are runModel\'s)', async () => {
    const kinds: [number, string][] = [
      [401, 'auth'],
      [402, 'billing'],
      [400, 'badRequest'],
      [422, 'badRequest'],
    ];
    for (const [status, kind] of kinds) {
      const { fetchFn, sent } = fetchStub(json({ error: { message: 'echo PROMPT-TEXT' } }, status));
      await assert.rejects(new DeepSeekProvider('KEY', fetchFn).call(input('deepseek-flash')), (e: ProviderError) => {
        assert.ok(!e.message.includes('PROMPT-TEXT'));
        return e.kind === kind && e.status === status;
      });
      assert.equal(sent.length, 1, `${status} is not retried`);
    }
    const once: [Response | Error, string][] = [
      [json({}, 429), 'rateLimit'],
      [json({}, 503), 'overloaded'],
      [new Error('socket'), 'network'],
    ];
    for (const [answer, kind] of once) {
      const { fetchFn, sent } = fetchStub(answer);
      await assert.rejects(new DeepSeekProvider('KEY', fetchFn).call(input('deepseek-flash')), (e: ProviderError) => e.kind === kind);
      assert.equal(sent.length, 1);
    }
  });

  test('without a key there is no provider', () => {
    assert.throws(() => new DeepSeekProvider(undefined), (e: ProviderError) => e.kind === 'noKey');
  });
});

/** A stand-in for the OpenAI client that records the request and returns `reply`. */
function openaiStub(reply: unknown) {
  const sent: Record<string, unknown>[] = [];
  const client = {
    responses: {
      create: async (params: Record<string, unknown>) => {
        sent.push(params);
        return reply;
      },
    },
  } as unknown as OpenAI;
  return { provider: new OpenAiProvider(undefined, client), sent };
}

const openaiResponse = (output: unknown[], extra: Record<string, unknown> = {}) => ({
  id: 'resp_1',
  object: 'response',
  status: 'completed',
  incomplete_details: null,
  output,
  usage: {
    input_tokens: 12000,
    input_tokens_details: { cached_tokens: 11000, cache_write_tokens: 0 },
    output_tokens: 150,
    output_tokens_details: { reasoning_tokens: 60 },
    total_tokens: 12150,
  },
  ...extra,
});

describe('OpenAiProvider', () => {
  test('uses the Responses API with function tools, tool_choice auto, effort, store false', async () => {
    const { provider, sent } = openaiStub(openaiResponse([]));
    await provider.call(input('gpt-6-luna'));
    const params = sent[0];
    assert.equal(params.model, 'gpt-6-luna');
    assert.equal(params.instructions, 'SYSTEM');
    assert.deepEqual(params.input, [{ role: 'user', content: 'USER' }]);
    assert.equal(params.tool_choice, 'auto');
    assert.equal(params.max_output_tokens, 8000);
    assert.deepEqual(params.reasoning, { effort: 'medium' });
    assert.equal(params.store, false);
    assert.deepEqual(params.include, ['reasoning.encrypted_content']);
    const tools = params.tools as Record<string, unknown>[];
    assert.equal(tools.length, 8);
    assert.deepEqual(Object.keys(tools[0]), ['type', 'name', 'description', 'parameters', 'strict']);
    assert.ok(tools.every((t) => t.type === 'function' && t.strict === false));
  });

  test('maps function calls, text, refusals, usage and incomplete reasons', async () => {
    const { provider } = openaiStub(
      openaiResponse([
        { type: 'reasoning', id: 'rs1', summary: [], encrypted_content: 'x' },
        { type: 'message', id: 'm1', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'Adding.', annotations: [] }] },
        { type: 'function_call', id: 'fc1', call_id: 'call1', name: 'reply', arguments: '{"text":"hi"}' },
        { type: 'function_call', id: 'fc2', call_id: 'call2', name: 'reply', arguments: '{"text":' },
      ]),
    );
    const response = await provider.call(input('gpt-6-luna'));
    assert.deepEqual(response.content, [
      { type: 'text', text: 'Adding.' },
      { type: 'tool_call', id: 'call1', name: 'reply', args: { text: 'hi' } },
      { type: 'tool_call', id: 'call2', name: 'reply', args: undefined },
    ]);
    assert.deepEqual(response.usage, { inputTokens: 1000, outputTokens: 150, cacheReadTokens: 11000, cacheWriteTokens: 0 });
    assert.equal(response.stopReason, 'end');

    const refusal = openaiResponse([{ type: 'message', id: 'm', role: 'assistant', status: 'completed', content: [{ type: 'refusal', refusal: 'no' }] }]);
    assert.equal((await openaiStub(refusal).provider.call(input('gpt-6-luna'))).stopReason, 'refusal');
    for (const [reason, mapped] of [
      ['max_output_tokens', 'length'],
      ['content_filter', 'refusal'],
    ] as const) {
      const r = openaiResponse([], { status: 'incomplete', incomplete_details: { reason } });
      assert.equal((await openaiStub(r).provider.call(input('gpt-6-luna'))).stopReason, mapped, reason);
    }
    await assert.rejects(openaiStub(openaiResponse([], { status: 'failed' })).provider.call(input('gpt-6-luna')), (e: ProviderError) => e.kind === 'overloaded');
  });

  test('the retry sends the output back with a function_call_output per call', async () => {
    const output = [
      { type: 'reasoning', id: 'rs1', summary: [], encrypted_content: 'enc' },
      { type: 'function_call', id: 'fc1', call_id: 'ok1', name: 'reply', arguments: '{"text":"hi"}' },
      { type: 'function_call', id: 'fc2', call_id: 'bad1', name: 'decline', arguments: '{"reason":"x"}' },
    ];
    const { provider, sent } = openaiStub(openaiResponse(output));
    const previous = await provider.call(input('gpt-6-luna'));
    await provider.call(input('gpt-6-luna', { retry: { previous, feedback: [{ id: 'bad1', errors: ['/reason: must be equal to one of the allowed values'] }] } }));
    const items = sent[1].input as Record<string, unknown>[];
    assert.equal(items.length, 7);
    assert.deepEqual(items.slice(1, 4), output);
    assert.deepEqual(items[4], { type: 'function_call_output', call_id: 'ok1', output: 'Valid. Repeat this call unchanged in your corrected answer.' });
    assert.equal(items[5].call_id, 'bad1');
    assert.match(String(items[5].output), /allowed values/);
    assert.equal(items[6].role, 'user');
  });

  test('typed SDK errors become ProviderError kinds; quota 429s are billing', () => {
    const headers = new Headers();
    const cases: [unknown, string][] = [
      [OpenAI.APIError.generate(401, { error: { type: 'invalid_request_error' } }, 'x', headers), 'auth'],
      [OpenAI.APIError.generate(429, { error: { code: 'insufficient_quota', type: 'insufficient_quota' } }, 'x', headers), 'billing'],
      [OpenAI.APIError.generate(429, { error: { code: 'credit_balance_exhausted' } }, 'x', headers), 'billing'],
      [OpenAI.APIError.generate(429, { error: { code: 'rate_limit_exceeded' } }, 'x', headers), 'rateLimit'],
      [OpenAI.APIError.generate(500, { error: {} }, 'x', headers), 'overloaded'],
      [OpenAI.APIError.generate(400, { error: {} }, 'x', headers), 'badRequest'],
      [new OpenAI.APIConnectionTimeoutError(), 'network'],
      [new Error('other'), 'badResponse'],
    ];
    for (const [error, kind] of cases) assert.equal(openaiMapError(error).kind, kind);
  });

  test('without a key there is no provider', () => {
    assert.throws(() => new OpenAiProvider(''), (e: ProviderError) => e.kind === 'noKey');
  });

  test('a failed response keeps its error code as a kind (N9)', async () => {
    for (const [code, kind] of [
      [undefined, 'overloaded'],
      ['server_error', 'overloaded'],
      ['rate_limit_exceeded', 'rateLimit'],
      ['insufficient_quota', 'billing'],
      ['invalid_prompt', 'badRequest'],
    ] as const) {
      assert.equal(failedError(code).kind, kind, String(code));
      assert.equal(failedError(code).status, undefined);
    }
    const failed = openaiResponse([], { status: 'failed', error: { code: 'invalid_prompt', message: 'secret text' } });
    await assert.rejects(openaiStub(failed).provider.call(input('gpt-6-luna')), (e: ProviderError) => e.kind === 'badRequest' && !e.message.includes('secret'));
  });

  test('a response without usage reads as unreadable, not free (L1)', async () => {
    const response = await openaiStub(openaiResponse([], { usage: undefined })).provider.call(input('gpt-6-luna'));
    assert.ok(Number.isNaN(response.usage.inputTokens));
    assert.ok(Number.isNaN(response.usage.outputTokens));
  });
});
