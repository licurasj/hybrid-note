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

/** The `maxLength` of `reply.text` in the unit 1 schema; filterOutput cuts to the tier's limit. */
export const REPLY_SCHEMA_MAX_CHARS = 500;

/**
 * The errors of the answer's calls to known tools, for the one
 * self-correction round (Q-34 A): the schema's, and a list the call may not
 * target (L3 of the T-19 unit 5 review). A reply that is only too long is
 * not retried, since filterOutput cuts it anyway (L2). Unknown tools are not
 * retried: they are dropped, as a list delete or a made-up tool must be.
 */
export function retryFeedback(response: ProviderResponse, schemaCheck: SchemaCheck, request?: AiRequest): ToolFeedback[] {
  const listIds = new Set(request?.lists.map((list) => list.id) ?? []);
  const openId = request?.openList?.definition.id;
  const feedback: ToolFeedback[] = [];
  for (const block of response.content) {
    if (block.type !== 'tool_call' || !(TOOL_NAMES as readonly string[]).includes(block.name)) continue;
    const name = block.name as ToolName;
    const args = name === 'reply' ? cutReply(block.args, REPLY_SCHEMA_MAX_CHARS) : block.args;
    const errors = [
      ...(request !== undefined && isRecord(args) ? targetErrors(name, args, listIds, openId, openItemIds(request)) : []),
      ...schemaCheck(name, args),
    ];
    if (errors.length > 0) feedback.push({ id: block.id, errors });
  }
  return feedback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** The ids of the open list's items in the context (choose_items may offer only these). */
function openItemIds(request: AiRequest | undefined): string[] {
  return (request?.openList?.items ?? []).map((item) => item.id).filter((id): id is string => typeof id === 'string');
}

/** A reply's text cut to `max` characters; anything else unchanged. */
function cutReply(args: unknown, max: number): unknown {
  if (!isRecord(args) || typeof args.text !== 'string') return args;
  const chars = [...args.text];
  return chars.length > max ? { ...args, text: chars.slice(0, max).join('') } : args;
}

/**
 * Which lists a call may name (Q-32, Q-36): item tools any of the user's
 * lists in the context, `patch_list` only the open list, `choose_list` 2 or
 * 3 distinct ones of them; `delete_items` names its items by ids or by match
 * (Q-39). English, for the self-correction round.
 */
function targetErrors(
  name: ToolName,
  args: Record<string, unknown>,
  listIds: Set<string>,
  openId: string | undefined,
  openItemIds?: string[],
): string[] {
  switch (name) {
    case 'patch_list':
      return openId !== undefined && args.listId === openId
        ? []
        : ['patch_list may only change the open list; use create_list for a new one'];
    case 'upsert_items':
    case 'delete_items': {
      const errors =
        typeof args.listId === 'string' && listIds.has(args.listId)
          ? []
          : [`${name}: listId must be the id of one of the user's lists`];
      // By id when the list's items are in the context, else by the items'
      // words, which the app matches (Q-39); the schema cannot say "one of".
      if (name === 'delete_items' && (args.ids === undefined) === (args.match === undefined)) {
        errors.push('delete_items needs either ids or match, not both');
      }
      return errors;
    }
    case 'choose_list': {
      const ids = args.candidates;
      // With New list as a choice one list is enough (Q-43).
      const ok =
        Array.isArray(ids) &&
        ids.length >= (args.newList === true ? 1 : 2) &&
        ids.length <= 3 &&
        new Set(ids).size === ids.length &&
        ids.every((id) => typeof id === 'string' && listIds.has(id));
      return ok ? [] : ["choose_list: candidates must be 2 or 3 different ids of the user's lists (1 to 3 with newList)"];
    }
    case 'choose_items': {
      // Only items the context shows, so only the open list (Q-42).
      const ids = args.candidates;
      const known = new Set(openItemIds ?? []);
      const ok =
        openId !== undefined &&
        args.listId === openId &&
        Array.isArray(ids) &&
        ids.length >= 2 &&
        ids.length <= 6 &&
        new Set(ids).size === ids.length &&
        ids.every((id) => typeof id === 'string' && known.has(id));
      return ok ? [] : ["choose_items: listId must be the open list and candidates 2 to 6 different ids of its items in the context"];
    }
    default:
      return [];
  }
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
    const call = acceptCall(block.name, block.args, listIds, openId, openItemIds(request), limits, schemaCheck, result);
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
  itemIds: string[],
  limits: TierLimits,
  schemaCheck: SchemaCheck,
  result: FilteredOutput,
): ToolCall | null {
  if (!(TOOL_NAMES as readonly string[]).includes(name) || !isRecord(args)) return null;
  const tool = name as ToolName;
  if (targetErrors(tool, args, listIds, openId, itemIds).length > 0) return null;
  let checked = args;
  if (tool === 'reply') {
    if (typeof args.text !== 'string') return null;
    checked = cutReply(args, limits.replyMaxChars) as Record<string, unknown>;
    if (checked !== args) result.replyTruncated = true;
  }
  return schemaCheck(tool, checked).length === 0 ? { name: tool, args: checked } : null;
}
