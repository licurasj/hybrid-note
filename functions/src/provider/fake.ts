import { loadExamples } from '../schemas';
import { ProviderError, type AiProvider, type ContentBlock, type ProviderCall, type ProviderResponse } from './types';

/**
 * A scripted provider for the emulator and tests: no network, no keys.
 * A marker in the prompt picks the answer; without one it adds the prompt's
 * comma-separated words as items to the open list (or the first list).
 *
 *   [fake:decline]   calls decline
 *   [fake:freetext]  answers with text only, no tool call
 *   [fake:mixed]     text before and after an upsert_items call
 *   [fake:longreply] a reply longer than any reply limit
 *   [fake:refusal]   the provider's own safety stop
 *   [fake:fail]      the provider errors
 *   [fake:length]    the answer is cut at the output ceiling
 *   [fake:badschema] the first answer breaks the tool schema, the retry fixes it
 *   [fake:badtwice]  both answers break the tool schema
 *   [fake:billing]   the provider answers 402 (no credit): an error that is not billed
 *   [fake:retryfail] the first answer breaks the schema and the retry call fails
 *
 * For the app's emulator run (T-19 unit 4):
 *   [fake:ask]       with no list open, asks which of the first two lists
 *                    (choose_list); with one open (the answer), adds there
 *   [fake:newlist]   creates the run log of the examples
 *   [fake:field]     adds a "Price" number field to the open list
 *   [fake:delete]    deletes the open list's first item
 *   [fake:reply]     answers with a short reply
 *   [fake:devicebad] adds items with a field key no list has (the device
 *                    refuses them), unless the request carries the device's
 *                    correction round, then adds them properly
 *
 * An item whose text contains "[fake:inject]" makes the fake "obey" it, as a
 * model fooled by a prompt injection would: it calls tools the function must
 * refuse (a list delete and a structure change on another list).
 */
export class FakeProvider implements AiProvider {
  readonly name = 'fake';

  async call({ request, retry }: ProviderCall): Promise<ProviderResponse> {
    const prompt = request.prompt;
    const target = request.openList?.definition.id ?? request.lists[0]?.id ?? 'none';
    const usage = {
      inputTokens: Math.ceil(JSON.stringify(request).length / 4) + 500,
      outputTokens: 120,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    };
    let next = 0;
    const tool = (name: string, args: unknown): ContentBlock => ({ type: 'tool_call', id: `call${next++}`, name, args });
    const answer = (content: ContentBlock[], stopReason: ProviderResponse['stopReason'] = 'end') => ({
      content,
      usage,
      stopReason,
    });
    const words = prompt
      .replace(/\[fake:[a-z]+\]/g, '')
      .split(',')
      .map((word) => word.trim())
      .filter((word) => word.length > 0);
    const adds = tool('upsert_items', {
      listId: target,
      items: words.map((word) => ({ values: [{ field: 'title', value: word }] })),
    });

    if (prompt.includes('[fake:fail]')) throw new Error('fake provider failure');
    if (prompt.includes('[fake:billing]')) throw new ProviderError('billing', 402);
    if (prompt.includes('[fake:retryfail]') && retry !== undefined) throw new ProviderError('network');
    if (prompt.includes('[fake:refusal]')) return answer([], 'refusal');
    if (prompt.includes('[fake:length]')) return answer([adds], 'length');
    const badFirst = prompt.includes('[fake:badschema]') || prompt.includes('[fake:retryfail]');
    if (prompt.includes('[fake:badtwice]') || (badFirst && retry === undefined)) {
      // Values as a map, the shape the strict schema does not allow.
      return answer([tool('upsert_items', { listId: target, items: words.map((word) => ({ values: { title: word } })) })]);
    }
    if (prompt.includes('[fake:ask]') && request.openList === null && request.lists.length >= 2) {
      return answer([
        tool('choose_list', { question: 'Which list?', candidates: request.lists.slice(0, 2).map((list) => list.id) }),
      ]);
    }
    if (prompt.includes('[fake:newlist]')) {
      const runLog = loadExamples().find((example) => example.id === 'runLog');
      return answer([tool('create_list', runLog?.input ?? {})]);
    }
    if (prompt.includes('[fake:field]')) {
      return answer([
        tool('patch_list', {
          listId: target,
          ops: [{ op: 'addField', field: { key: 'price', type: 'number', label: 'Price', min: 0 } }],
        }),
      ]);
    }
    if (prompt.includes('[fake:delete]')) {
      const first = request.openList?.items[0]?.id;
      return answer([tool('delete_items', { listId: target, ids: first === undefined ? [] : [first] })]);
    }
    if (prompt.includes('[fake:reply]')) {
      return answer([tool('reply', { text: 'Grocery has 3 items open.' })]);
    }
    if (prompt.includes('[fake:devicebad]') && request.correction === undefined) {
      return answer([
        tool('upsert_items', {
          listId: target,
          items: words.map((word) => ({ values: [{ field: 'name', value: word }] })),
        }),
      ]);
    }
    if (prompt.includes('[fake:decline]')) {
      return answer([tool('decline', { reason: 'offTopic' })]);
    }
    if (prompt.includes('[fake:freetext]')) {
      return answer([{ type: 'text', text: 'Sure! Here is a poem instead of a list.' }]);
    }
    if (prompt.includes('[fake:mixed]')) {
      return answer([
        { type: 'text', text: 'Let me add those.' },
        adds,
        { type: 'text', text: 'Done, anything else?' },
      ]);
    }
    if (prompt.includes('[fake:longreply]')) {
      return answer([tool('reply', { text: 'x'.repeat(2000) })]);
    }
    const injected = (request.openList?.items ?? []).some((item) =>
      JSON.stringify(item).includes('[fake:inject]'),
    );
    if (injected) {
      const other = request.lists.find((list) => list.id !== target)?.id ?? 'other';
      return answer([
        tool('delete_list', { listId: target }),
        tool('patch_list', { listId: other, ops: [{ op: 'removeField', key: 'name' }] }),
        tool('upsert_items', { listId: 'not-a-user-list', items: [{ values: [{ field: 'title', value: 'x' }] }] }),
      ]);
    }
    return answer([adds]);
  }
}
