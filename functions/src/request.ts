import type { TierLimits } from './config';
import { refuse } from './errors';

/** One of the user's lists as the context names it (Q-36): no items. */
export interface ListSummary {
  id: string;
  name: string;
  fields: unknown[];
  /**
   * Required (fail closed, L16 of the unit 5 follow-up review). false: the
   * user turned AI off for this list; it is dropped before the model sees
   * anything. Unit 4 leaves such lists out altogether.
   */
  aiAllowed: boolean;
}

/** The list open on screen, if any: its definition and recent items. */
export interface OpenList {
  definition: Record<string, unknown> & { id: string };
  items: Record<string, unknown>[];
}

export interface AiRequest {
  prompt: string;
  locale: string;
  /** The device's local date, YYYY-MM-DD, for "on Friday"; the server's UTC date when absent. */
  today?: string;
  lists: ListSummary[];
  /** Absent or null when no list is open (Q-36): the AI routes to a list. */
  openList: OpenList | null;
  /**
   * The device's self-correction round (Q-34 A): the tool calls of the
   * previous answer to this request and the ListErrors the device's
   * validation found in them (English). A new request, counted like any.
   */
  correction?: Correction;
}

export interface Correction {
  toolCalls: { name: string; args: unknown }[];
  errors: string[];
}

/** Limits of the correction part; its JSON also counts towards contextMaxBytes. */
export const CORRECTION_MAX_CALLS = 10;
export const CORRECTION_MAX_ERRORS = 20;
export const CORRECTION_ERROR_MAX_CHARS = 300;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isId(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 128;
}

/**
 * Checks the request's shape and the tier's input limits, in this order:
 * shape, prompt length, context size, aiAllowed. Messages name the rule
 * only, never the request's text.
 */
export function parseRequest(data: unknown, limits: TierLimits): AiRequest {
  if (!isRecord(data)) throw refuse('badRequest', 'request must be an object');
  const { prompt, locale, lists } = data;
  const openList = data.openList ?? null;

  if (typeof prompt !== 'string' || prompt.trim().length === 0) {
    throw refuse('badRequest', 'prompt must be a non-empty string');
  }
  // A BCP-47 language tag as Flutter's toLanguageTag() gives it ("en",
  // "zh-Hans-CN"); it goes into the prompt, so nothing else is let in (N2).
  if (typeof locale !== 'string' || locale.length > 35 || !/^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$/.test(locale)) {
    throw refuse('badRequest', 'locale must be a language tag');
  }
  const today = data.today ?? undefined;
  if (today !== undefined && (typeof today !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(today))) {
    throw refuse('badRequest', 'today must be YYYY-MM-DD');
  }
  if (!Array.isArray(lists)) throw refuse('badRequest', 'lists must be an array');
  for (const list of lists) {
    if (!isRecord(list) || !isId(list.id) || typeof list.name !== 'string' || !Array.isArray(list.fields)) {
      throw refuse('badRequest', 'each list needs id, name and fields');
    }
    if (typeof list.aiAllowed !== 'boolean') {
      throw refuse('badRequest', 'each list needs aiAllowed true or false');
    }
  }
  if (new Set(lists.map((list) => list.id)).size !== lists.length) {
    throw refuse('badRequest', 'list ids must be unique');
  }
  const correction = data.correction ?? undefined;
  if (correction !== undefined) {
    if (
      !isRecord(correction) ||
      !Array.isArray(correction.toolCalls) ||
      !Array.isArray(correction.errors) ||
      correction.toolCalls.length === 0 ||
      correction.toolCalls.length > CORRECTION_MAX_CALLS ||
      !correction.toolCalls.every((call) => isRecord(call) && typeof call.name === 'string' && call.name.length <= 64) ||
      correction.errors.length === 0 ||
      correction.errors.length > CORRECTION_MAX_ERRORS ||
      !correction.errors.every((error) => typeof error === 'string' && error.length <= CORRECTION_ERROR_MAX_CHARS)
    ) {
      throw refuse('badRequest', 'correction needs 1-10 tool calls and 1-20 short errors');
    }
  }
  if (openList !== null) {
    if (!isRecord(openList) || !isRecord(openList.definition) || !Array.isArray(openList.items)) {
      throw refuse('badRequest', 'openList needs definition and items');
    }
    const openId = openList.definition.id;
    if (!isId(openId) || !lists.some((list) => list.id === openId)) {
      throw refuse('badRequest', 'the open list must be one of the lists');
    }
    if (!openList.items.every(isRecord)) throw refuse('badRequest', 'items must be objects');
  }

  if ([...prompt].length > limits.promptMaxChars) {
    throw refuse('promptTooLong', `prompt is over ${limits.promptMaxChars} characters`);
  }
  if (lists.length > limits.maxLists) {
    throw refuse('contextTooLarge', `more than ${limits.maxLists} lists`);
  }
  if (openList !== null && (openList.items as unknown[]).length > limits.maxItems) {
    throw refuse('contextTooLarge', `more than ${limits.maxItems} items`);
  }
  const contextBytes = Buffer.byteLength(JSON.stringify({ lists, openList, correction }), 'utf8');
  if (contextBytes > limits.contextMaxBytes) {
    throw refuse('contextTooLarge', `context is over ${limits.contextMaxBytes} bytes`);
  }
  const openId = openList === null ? undefined : (openList.definition as Record<string, unknown>).id;
  const openSummary = (lists as Record<string, unknown>[]).find((list) => list.id === openId);
  if (openList !== null && ((openList.definition as Record<string, unknown>).aiAllowed === false || openSummary?.aiAllowed === false)) {
    throw refuse('aiNotAllowed', 'AI is off for the open list');
  }
  // Lists with AI off are dropped (Q-36): the model never sees them, and the
  // output filter refuses any tool call that names one (its id is unknown).
  const allowed = (lists as Record<string, unknown>[]).filter((list) => list.aiAllowed !== false);

  return {
    prompt,
    locale,
    ...(today !== undefined ? { today } : {}),
    lists: allowed as unknown as ListSummary[],
    openList: openList as OpenList | null,
    ...(correction !== undefined
      ? {
          correction: {
            toolCalls: (correction.toolCalls as Record<string, unknown>[]).map((call) => ({ name: call.name as string, args: call.args })),
            errors: correction.errors as string[],
          },
        }
      : {}),
  };
}
