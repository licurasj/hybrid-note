import type { TierLimits } from './config';
import type { AiRequest } from './request';
import { TOOL_NAMES, type ProviderResponse, type ToolFeedback, type ToolName } from './provider/types';

export interface ToolCall {
  name: ToolName;
  args: Record<string, unknown>;
}

/** offTopic and notSupported come from the model's decline call (unit 1 schema). */
export type DeclineReason = 'offTopic' | 'notSupported' | 'providerRefusal' | 'noValidTool';

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
 * The per-tool schema check: the errors of one call, none when it is valid.
 * aiCommand uses schemaErrors (src/schemas.ts, the unit 1 JSON Schemas);
 * structuralCheck accepts everything, for tests of the other rules.
 */
export type SchemaCheck = (name: ToolName, args: unknown) => string[];

export const structuralCheck: SchemaCheck = () => [];

/**
 * The schema errors of the answer's calls to known tools, for the one
 * self-correction round (Q-34 A). Unknown tools are not retried: they are
 * dropped, as a list delete or a made-up tool must be.
 */
export function retryFeedback(response: ProviderResponse, schemaCheck: SchemaCheck): ToolFeedback[] {
  const feedback: ToolFeedback[] = [];
  for (const block of response.content) {
    if (block.type !== 'tool_call' || !(TOOL_NAMES as readonly string[]).includes(block.name)) continue;
    const errors = schemaCheck(block.name as ToolName, block.args);
    if (errors.length > 0) feedback.push({ id: block.id, errors });
  }
  return feedback;
}

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

  let declined: DeclineReason | null = null;
  for (const block of response.content) {
    if (block.type === 'text') {
      result.droppedText++;
      continue;
    }
    const call = acceptCall(block.name, block.args, listIds, openId, limits, schemaCheck, result);
    if (call === null) {
      result.droppedTools++;
    } else if (call.name === 'decline') {
      declined ??= call.args.reason === 'notSupported' ? 'notSupported' : 'offTopic';
    } else {
      result.toolCalls.push(call);
    }
  }

  if (response.stopReason === 'refusal') return decline('providerRefusal');
  if (declined !== null) return decline(declined);
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
      // "Which list?" with 2 or 3 distinct candidates of the user's lists (Q-36).
      const ids = args.candidates;
      if (!Array.isArray(ids) || ids.length < 2 || ids.length > 3) return null;
      if (new Set(ids).size !== ids.length) return null;
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
  return schemaCheck(tool, checked).length === 0 ? { name: tool, args: checked } : null;
}
