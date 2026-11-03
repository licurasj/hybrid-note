import { createHash } from 'node:crypto';
import * as logger from 'firebase-functions/logger';

import type { AppCheckDecision } from './appCheck';

/**
 * Everything the ordinary log may say about a request (Q-31 B): metadata
 * only. Prompt, list and item text never go here; the prompt goes to the
 * 7-day prompt log (promptLog.ts) and nowhere else.
 */
export interface RequestMeta {
  requestId: string;
  uidHash?: string;
  tier?: string;
  provider?: string;
  model?: string;
  appCheck?: Pick<AppCheckDecision, 'verdict' | 'platform' | 'mode'>;
  hasOpenList?: boolean;
  listCount?: number;
  itemCount?: number;
  promptChars?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  costMicros?: number;
  stopReason?: string;
  /** Provider calls made: 2 when the schema self-correction ran. */
  attempts?: number;
  /** ProviderError kind of a failed call (never its message). */
  providerError?: string;
  /** Why the self-correction call did not count: its error kind, or noTime. */
  retryError?: string;
  /** Busy answers tried again (a rate-limited provider otherwise looks healthy). */
  busyRetries?: number;
  /** The provider's usage was missing or not a count; the ceiling was booked (L1). */
  usageUnreadable?: boolean;
  /** Class name of an unexpected error (outcome error), never its message (L9). */
  errorName?: string;
  toolCounts?: Record<string, number>;
  droppedText?: number;
  droppedTools?: number;
  replyTruncated?: boolean;
  outcome?: 'ok' | 'declined' | 'refused' | 'error';
  reason?: string;
  latencyMs?: number;
}

export type LogSink = (message: string, entry: RequestMeta) => void;

export const cloudLogSink: LogSink = (message, entry) => logger.info(message, entry);

export function uidHash(uid: string): string {
  return createHash('sha256').update(uid).digest('hex').slice(0, 16);
}
