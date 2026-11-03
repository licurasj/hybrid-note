import type { AiProvider, ContentBlock, ProviderCall, ProviderResponse } from './types';

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
 *
 * An item whose text contains "[fake:inject]" makes the fake "obey" it, as a
 * model fooled by a prompt injection would: it calls tools the function must
 * refuse (a list delete and a structure change on another list).
 */
export class FakeProvider implements AiProvider {
  readonly name = 'fake';

  async call({ request }: ProviderCall): Promise<ProviderResponse> {
    const prompt = request.prompt;
    const target = request.openList?.definition.id ?? request.lists[0]?.id ?? 'none';
    const usage = {
      inputTokens: Math.ceil(JSON.stringify(request).length / 4) + 500,
      outputTokens: 120,
    };
    const answer = (content: ContentBlock[], stopReason: ProviderResponse['stopReason'] = 'end') => ({
      content,
      usage,
      stopReason,
    });
    const adds: ContentBlock = {
      type: 'tool_call',
      name: 'upsert_items',
      args: {
        listId: target,
        items: prompt
          .replace(/\[fake:[a-z]+\]/g, '')
          .split(',')
          .map((word) => word.trim())
          .filter((word) => word.length > 0)
          .map((word) => ({ values: { name: word } })),
      },
    };

    if (prompt.includes('[fake:fail]')) throw new Error('fake provider failure');
    if (prompt.includes('[fake:refusal]')) return answer([], 'refusal');
    if (prompt.includes('[fake:decline]')) {
      return answer([{ type: 'tool_call', name: 'decline', args: { reason: 'offTopic' } }]);
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
      return answer([{ type: 'tool_call', name: 'reply', args: { text: 'x'.repeat(2000) } }]);
    }
    const injected = (request.openList?.items ?? []).some((item) =>
      JSON.stringify(item).includes('[fake:inject]'),
    );
    if (injected) {
      const other = request.lists.find((list) => list.id !== target)?.id ?? 'other';
      return answer([
        { type: 'tool_call', name: 'delete_list', args: { listId: target } },
        { type: 'tool_call', name: 'patch_list', args: { listId: other, ops: [{ op: 'removeField', key: 'name' }] } },
        { type: 'tool_call', name: 'upsert_items', args: { listId: 'not-a-user-list', items: [{ values: { name: 'x' } }] } },
      ]);
    }
    return answer([adds]);
  }
}
