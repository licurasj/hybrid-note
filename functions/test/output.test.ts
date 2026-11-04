// The output filter: free text dropped, decline handling, reply limit and the
// target-list rules of Q-36, fed with provider answers directly.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { TIERS } from '../src/config';
import { filterOutput, retryFeedback, structuralCheck } from '../src/output';
import type { ContentBlock, ProviderResponse } from '../src/provider/types';
import { parseRequest, type AiRequest } from '../src/request';

const limits = TIERS.owner;

const open: AiRequest = parseRequest(
  {
    prompt: 'p',
    locale: 'en',
    lists: [
      { id: 'grocery', name: 'Grocery', fields: [], aiAllowed: true },
      { id: 'todo', name: 'To do', fields: [], aiAllowed: true },
    ],
    openList: { definition: { id: 'grocery' }, items: [] },
  },
  limits,
);
const closed: AiRequest = { ...open, openList: null };

function answer(content: ContentBlock[], stopReason: ProviderResponse['stopReason'] = 'end'): ProviderResponse {
  return { content, usage: { inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0 }, stopReason };
}

let ids = 0;
const call = (name: string, args: unknown): ContentBlock => ({ type: 'tool_call', id: `c${ids++}`, name, args });
const text = (t: string): ContentBlock => ({ type: 'text', text: t });

describe('filterOutput', () => {
  test('a call naming a list with AI off is dropped (Q-36, dropped by parseRequest)', () => {
    const request = parseRequest(
      {
        prompt: 'add milk',
        locale: 'en',
        lists: [
          { id: 'grocery', name: 'Grocery', fields: [], aiAllowed: true },
          { id: 'diary', name: 'Diary', fields: [], aiAllowed: false },
        ],
        openList: null,
      },
      limits,
    );
    const items = [{ values: [{ field: 'title', value: 'x' }] }];
    const out = filterOutput(
      answer([call('upsert_items', { listId: 'diary', items }), call('delete_items', { listId: 'diary', ids: ['d1'] })]),
      request,
      limits,
    );
    assert.equal(out.outcome, 'declined');
    assert.equal(out.droppedTools, 2);
  });

  test('tool calls pass and free text around them is dropped', () => {
    const out = filterOutput(
      answer([text('Sure!'), call('upsert_items', { listId: 'grocery', items: [] }), text('Done.')]),
      open,
      limits,
    );
    assert.equal(out.outcome, 'ok');
    assert.deepEqual(out.toolCalls.map((c) => c.name), ['upsert_items']);
    assert.equal(out.droppedText, 2);
  });

  test('free text only becomes an off-topic decline', () => {
    const out = filterOutput(answer([text('Here is a poem.')]), open, limits);
    assert.equal(out.outcome, 'declined');
    assert.equal(out.declineReason, 'offTopic');
    assert.deepEqual(out.toolCalls, []);
  });

  test('decline wins over other calls', () => {
    const out = filterOutput(
      answer([call('decline', { reason: 'offTopic' }), call('upsert_items', { listId: 'grocery', items: [] })]),
      open,
      limits,
    );
    assert.equal(out.outcome, 'declined');
    assert.deepEqual(out.toolCalls, []);
  });

  test('decline keeps notSupported, anything else is offTopic', () => {
    const reason = (r: unknown) => filterOutput(answer([call('decline', { reason: r })]), open, limits).declineReason;
    assert.equal(reason('notSupported'), 'notSupported');
    assert.equal(reason('offTopic'), 'offTopic');
    assert.equal(reason('whatever'), 'offTopic');
  });

  test('the provider refusal is a decline', () => {
    const out = filterOutput(answer([], 'refusal'), open, limits);
    assert.equal(out.declineReason, 'providerRefusal');
  });

  test('an over-long reply is cut to the reply limit', () => {
    const out = filterOutput(answer([call('reply', { text: 'é'.repeat(800) })]), open, limits);
    assert.equal([...(out.toolCalls[0].args.text as string)].length, 500);
    assert.equal(out.replyTruncated, true);
  });

  test('item tools may target any of the user lists, not others (Q-36)', () => {
    const out = filterOutput(
      answer([
        call('upsert_items', { listId: 'todo', items: [] }),
        call('delete_items', { listId: 'grocery', ids: ['i1'] }),
        call('upsert_items', { listId: 'someone-else', items: [] }),
        call('delete_items', { ids: ['i1'] }),
      ]),
      closed,
      limits,
    );
    assert.deepEqual(out.toolCalls.map((c) => c.args.listId), ['todo', 'grocery']);
    assert.equal(out.droppedTools, 2);
  });

  test('patch_list only on the open list, never with no list open', () => {
    const patch = (listId: string) => call('patch_list', { listId, ops: [] });
    assert.equal(filterOutput(answer([patch('grocery')]), open, limits).outcome, 'ok');
    assert.equal(filterOutput(answer([patch('todo')]), open, limits).outcome, 'declined');
    assert.equal(filterOutput(answer([patch('grocery')]), closed, limits).declineReason, 'noValidTool');
  });

  test('choose_list names 2 or 3 distinct user lists as candidates', () => {
    const choose = (candidates: unknown) => call('choose_list', { question: 'Grocery or To do?', candidates });
    assert.equal(filterOutput(answer([choose(['grocery', 'todo'])]), closed, limits).outcome, 'ok');
    for (const bad of [[], ['grocery'], ['grocery', 'grocery'], ['grocery', 'nope'], 'grocery']) {
      assert.equal(filterOutput(answer([choose(bad)]), closed, limits).outcome, 'declined');
    }
  });

  test('unknown tools (a list delete) and non-object arguments are dropped', () => {
    const out = filterOutput(
      answer([
        call('delete_list', { listId: 'grocery' }),
        call('create_list', 'definition'),
        call('create_list', { definition: {} }),
      ]),
      open,
      limits,
    );
    assert.deepEqual(out.toolCalls.map((c) => c.name), ['create_list']);
    assert.equal(out.droppedTools, 2);
  });

  test('a failing schema check drops the call', () => {
    const out = filterOutput(answer([call('create_list', {})]), open, limits, () => ['bad']);
    assert.equal(out.declineReason, 'noValidTool');
  });
});

describe('retryFeedback', () => {
  test('choose_items offers 2 to 6 items of the open list in the context (Q-42)', () => {
    const withItems: AiRequest = {
      ...open,
      openList: { definition: { id: 'grocery' }, items: [{ id: 'i1' }, { id: 'i2' }, { id: 'i3' }] },
    };
    const choose = (args: Record<string, unknown>) =>
      retryFeedback(answer([call('choose_items', { question: 'Which?', ...args })]), structuralCheck, withItems);
    assert.deepEqual(choose({ listId: 'grocery', candidates: ['i1', 'i2'] }), []);
    assert.equal(choose({ listId: 'grocery', candidates: ['i1'] }).length, 1);
    assert.equal(choose({ listId: 'grocery', candidates: ['i1', 'nope'] }).length, 1);
    assert.equal(choose({ listId: 'todo', candidates: ['i1', 'i2'] }).length, 1);
    assert.equal(
      retryFeedback(answer([call('choose_items', { question: 'Which?', listId: 'grocery', candidates: ['i1', 'i2'] })]), structuralCheck, closed)
        .length,
      1,
    );
  });

  test('delete_items names its items by ids or by match, not both or neither (Q-39)', () => {
    const feedback = retryFeedback(
      answer([
        call('delete_items', { listId: 'grocery', match: ['milk'] }),
        call('delete_items', { listId: 'grocery', ids: ['i1'] }),
        call('delete_items', { listId: 'grocery' }),
        call('delete_items', { listId: 'grocery', ids: ['i1'], match: ['milk'] }),
      ]),
      structuralCheck,
      open,
    );
    assert.equal(feedback.length, 2);
    assert.ok(feedback.every((f) => /either ids or match/.test(f.errors[0])));
  });

  test('a reply that is only too long is not retried: filterOutput cuts it (L2)', () => {
    const long = answer([call('reply', { text: 'x'.repeat(600) })]);
    const maxLength = (_: string, args: unknown) =>
      ((args as { text: string }).text.length > 500 ? ['text: must be at most 500 characters'] : []);
    assert.deepEqual(retryFeedback(long, maxLength, open), []);
  });

  test('calls naming a list they may not target go into the one retry (L3)', () => {
    const response = answer([
      call('upsert_items', { listId: 'elsewhere', items: [] }),
      call('patch_list', { listId: 'todo', ops: [] }),
      call('choose_list', { candidates: ['grocery'] }),
      call('upsert_items', { listId: 'todo', items: [] }),
    ]);
    const feedback = retryFeedback(response, structuralCheck, open);
    assert.equal(feedback.length, 3);
    assert.match(feedback[0].errors[0], /listId must be the id of one of the user's lists/);
    assert.match(feedback[1].errors[0], /patch_list may only change the open list/);
    assert.match(feedback[2].errors[0], /choose_list/);
    assert.equal(retryFeedback(answer([call('patch_list', { listId: 'grocery', ops: [] })]), structuralCheck, closed).length, 1);
  });

  test('without the request only the schema is checked', () => {
    assert.deepEqual(retryFeedback(answer([call('upsert_items', { listId: 'elsewhere' })]), structuralCheck), []);
  });

  test('filterOutput counts the calls it dropped', () => {
    const out = filterOutput(
      answer([call('upsert_items', { listId: 'grocery', items: [] }), call('upsert_items', { listId: 'elsewhere', items: [] })]),
      open,
      limits,
    );
    assert.equal(out.outcome, 'ok');
    assert.equal(out.toolCalls.length, 1);
    assert.equal(out.droppedTools, 1);
  });
});
