import type { Auth, UserRecord } from 'firebase-admin/auth';
import { FieldPath, type Firestore } from 'firebase-admin/firestore';

import { ANONYMOUS_MAX_AGE_HOURS, COLLECTIONS } from './config';

// The demo's clean-up (T-18): every portfolio visitor gets an anonymous Auth
// account at the first AI request. Accounts older than ANONYMOUS_MAX_AGE_HOURS
// are deleted with their aiUsageUser documents `${uid}_${day}`; the pool
// documents stay, and prompt-log entries go by their 7-day TTL (they hold only
// a uidHash). An account with any sign-in provider (Google, email) is never
// touched, whatever its age.

/** The part of the Admin Auth API the clean-up uses, so tests can make one call fail. */
export type CleanupAuth = Pick<Auth, 'listUsers' | 'deleteUser'>;

export interface CleanupResult {
  /** Anonymous accounts old enough to go. */
  found: number;
  deleted: number;
  /** Accounts left for the next run because a step failed. */
  failed: number;
  /** aiUsageUser documents deleted. */
  usageDocs: number;
}

/** An account with no sign-in provider, email or phone: an anonymous one. */
export function isAnonymous(user: UserRecord): boolean {
  return user.providerData.length === 0 && !user.email && !user.phoneNumber;
}

/** Whether the account was created more than the maximum age before `now`. */
export function isOld(user: UserRecord, now: Date): boolean {
  const created = Date.parse(user.metadata.creationTime);
  // An unreadable creation time is never taken as old.
  return Number.isFinite(created) && now.getTime() - created > ANONYMOUS_MAX_AGE_HOURS * 3_600_000;
}

/** Deletes every aiUsageUser document of `uid` (ids `${uid}_${day}`); returns how many. */
async function deleteUsageDocs(db: Firestore, uid: string): Promise<number> {
  const prefix = `${uid}_`;
  const snapshot = await db
    .collection(COLLECTIONS.userUsage)
    .where(FieldPath.documentId(), '>=', prefix)
    .where(FieldPath.documentId(), '<', `${uid}\``) // '`' is the character after '_'
    .get();
  // One document per UTC day the visitor used AI: a batch (at most 500 writes) per 500 days.
  for (let i = 0; i < snapshot.size; i += 500) {
    const batch = db.batch();
    for (const doc of snapshot.docs.slice(i, i + 500)) batch.delete(doc.ref);
    await batch.commit();
  }
  return snapshot.size;
}

/**
 * One clean-up run. The usage documents go first and the account last, so a
 * failure on either leaves the account for the next run to retry; one
 * account's failure never stops the others.
 */
export async function cleanUpAnonymous(auth: CleanupAuth, db: Firestore, now: Date): Promise<CleanupResult> {
  const result: CleanupResult = { found: 0, deleted: 0, failed: 0, usageDocs: 0 };
  const old: string[] = [];
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (isAnonymous(user) && isOld(user, now)) old.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken !== undefined);

  result.found = old.length;
  for (const uid of old) {
    try {
      result.usageDocs += await deleteUsageDocs(db, uid);
      await auth.deleteUser(uid);
      result.deleted++;
    } catch {
      result.failed++;
    }
  }
  return result;
}
