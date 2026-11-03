import type { TierLimits } from './config';
import { refuse } from './errors';

/** One of the user's lists as the context names it (Q-36): no items. */
export interface ListSummary {
  id: string;
  name: string;
  fields: unknown[];
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
}

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
  if (typeof locale !== 'string' || locale.length === 0 || locale.length > 35) {
    throw refuse('badRequest', 'locale must be a short string');
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
  }
  if (new Set(lists.map((list) => list.id)).size !== lists.length) {
    throw refuse('badRequest', 'list ids must be unique');
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
  const contextBytes = Buffer.byteLength(JSON.stringify({ lists, openList }), 'utf8');
  if (contextBytes > limits.contextMaxBytes) {
    throw refuse('contextTooLarge', `context is over ${limits.contextMaxBytes} bytes`);
  }
  if (openList !== null && (openList.definition as Record<string, unknown>).aiAllowed === false) {
    throw refuse('aiNotAllowed', 'AI is off for the open list');
  }

  return {
    prompt,
    locale,
    ...(today !== undefined ? { today } : {}),
    lists: lists as unknown as ListSummary[],
    openList: openList as OpenList | null,
  };
}
