import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/**
 * Why aiCommand refused a call. The client maps `details.reason` to a
 * translated message; the HttpsError code alone is not specific enough
 * (both caps are `resource-exhausted`).
 */
export type RefusalReason =
  | 'signIn'
  | 'appCheck'
  | 'notAllowed'
  | 'badRequest'
  | 'promptTooLong'
  | 'contextTooLarge'
  | 'aiNotAllowed'
  | 'dailyCount'
  | 'globalBudget'
  | 'busy'
  | 'provider';

const CODES: Record<RefusalReason, FunctionsErrorCode> = {
  signIn: 'unauthenticated',
  appCheck: 'permission-denied',
  notAllowed: 'permission-denied',
  badRequest: 'invalid-argument',
  promptTooLong: 'invalid-argument',
  contextTooLarge: 'invalid-argument',
  aiNotAllowed: 'failed-precondition',
  dailyCount: 'resource-exhausted',
  globalBudget: 'resource-exhausted',
  busy: 'aborted',
  provider: 'unavailable',
};

/** A typed refusal. Messages are English and carry no request text. */
export function refuse(reason: RefusalReason, message: string = reason): HttpsError {
  return new HttpsError(CODES[reason], message, { reason });
}

export function reasonOf(error: unknown): RefusalReason | 'internal' {
  if (error instanceof HttpsError) {
    const reason = (error.details as { reason?: RefusalReason } | undefined)?.reason;
    if (reason) return reason;
  }
  return 'internal';
}
