import type { Firestore } from 'firebase-admin/firestore';

import { COLLECTIONS, PROMPT_LOG_DAYS } from './config';

/**
 * Keeps the prompt text for debugging in the server-only aiPromptLog
 * collection (Q-31 B). A Firestore TTL policy on `expireAt` (created in
 * T-19 unit 6) deletes each document after 7 days; the emulator does not.
 */
export async function writePromptLog(
  db: Firestore,
  entry: { requestId: string; uidHash: string; prompt: string; now: Date },
): Promise<void> {
  const expireAt = new Date(entry.now.getTime() + PROMPT_LOG_DAYS * 24 * 60 * 60 * 1000);
  await db.collection(COLLECTIONS.promptLog).doc(entry.requestId).set({
    requestId: entry.requestId,
    uidHash: entry.uidHash,
    time: entry.now,
    prompt: entry.prompt,
    expireAt,
  });
}
