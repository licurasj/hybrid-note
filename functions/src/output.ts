import type { TierLimits } from './config';
import type { AiRequest } from './request';
import { TOOL_NAMES, type ProviderResponse, type ToolName } from './provider/types';

export interface ToolCall {
  name: ToolName;
  args: Record<string, unknown>;
}

export type DeclineReason = 'offTopic' | 'providerRefusal' | 'noValidTool';

export interface FilteredOutput {
  outcome: 'ok' | 'declined';
  toolCalls: ToolCall[];
  declineReason?: DeclineReason;
  /** Counts for the metadata log; never the dropped content itself. */
  droppedText: number;
  droppedTools: number;
  replyTruncated: boolean;
}

/**
 * The per-tool schema check. Structural until T-19 unit 3 wires the JSON
 * Schemas that unit 1 writes (copied to lib/schema/ by scripts/copy-schemas.mjs)
 * and adds the one self-correction retry.
 */
export type SchemaCheck = (name: ToolName, args: Record<string, unknown>) => boolean;

export const structuralCheck: SchemaCheck = () => true;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Turns the model's answer into tool calls the client may preview (Q-29,
 * Q-32, Q-36). Free text outside tool calls is dropped; an answer with no
 * valid tool call left, a `decline` call or the provider's refusal becomes a
 * decline. Item tools may target any of the user's lists in the context;
 * `patch_list` only the open list; list deletes do not exist.
 */
export function filterOutput(
  response: ProviderResponse,
  request: AiRequest,
  limits: TierLimits,
  schemaCheck: SchemaCheck = structuralCheck,
): FilteredOutput {
  const listIds = new Set(request.lists.map((list) => list.id));
  const openId = request.openList?.definition.id;
  const result: FilteredOutput = {
    outcome: 'ok',
    toolCalls: [],
    droppedText: 0,
    droppedTools: 0,
    replyTruncated: false,
  };
  const decline = (reason: DeclineReason): FilteredOutput => ({
    ...result,
    outcome: 'declined',
    toolCalls: [],
    declineReason: reason,
  });

  let declined = false;
  for (const block of response.content) {
    if (block.type === 'text') {
      result.droppedText++;
      continue;
    }
    const call = acceptCall(block.name, block.args, listIds, openId, limits, schemaCheck, result);
    if (call === null) {
      result.droppedTools++;
    } else if (call.name === 'decline') {
      declined = true;
    } else {
      result.toolCalls.push(call);
    }
  }

  if (response.stopReason === 'refusal') return decline('providerRefusal');
  if (declined) return decline('offTopic');
  if (result.toolCalls.length === 0) {
    return decline(result.droppedTools > 0 ? 'noValidTool' : 'offTopic');
  }
  return result;
}

function acceptCall(
  name: string,
  args: unknown,
  listIds: Set<string>,
  openId: string | undefined,
  limits: TierLimits,
  schemaCheck: SchemaCheck,
  result: FilteredOutput,
): ToolCall | null {
  if (!(TOOL_NAMES as readonly string[]).includes(name) || !isRecord(args)) return null;
  const tool = name as ToolName;
  switch (tool) {
    case 'patch_list':
      if (openId === undefined || args.listId !== openId) return null;
      break;
    case 'upsert_items':
    case 'delete_items':
      if (typeof args.listId !== 'string' || !listIds.has(args.listId)) return null;
      break;
    case 'choose_list': {
      const ids = args.listIds;
      if (!Array.isArray(ids) || ids.length === 0 || ids.length > 3) return null;
      if (!ids.every((id) => typeof id === 'string' && listIds.has(id))) return null;
      break;
    }
    case 'reply': {
      if (typeof args.text !== 'string') return null;
      const chars = [...args.text];
      if (chars.length > limits.replyMaxChars) {
        args = { ...args, text: chars.slice(0, limits.replyMaxChars).join('') };
        result.replyTruncated = true;
      }
      break;
    }
    case 'create_list':
    case 'decline':
      break;
  }
  const checked = args as Record<string, unknown>;
  return schemaCheck(tool, checked) ? { name: tool, args: checked } : null;
}
