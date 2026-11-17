import type { Auth, UserRecord } from 'firebase-admin/auth';
import { FieldPath, type Firestore } from 'firebase-admin/firestore';

import { ANONYMOUS_MAX_AGE_HOURS, COLLECTIONS, RETIRED_DRAIN_HOURS } from './config';

// The demo's clean-up (T-18): every portfolio visitor gets an anonymous Auth
// account at the first AI request. Accounts older than ANONYMOUS_MAX_AGE_HOURS
// are deleted, and their aiUsageUser documents `${uid}_${day}` later; the pool
// documents stay, and prompt-log entries go by their 7-day TTL (they hold only
// a uidHash). An account with any sign-in provider (Google, email) is never
// touched, whatever its age.
//
// Two steps per account, so a visitor's daily count is never reset or made
// anew while the account can still call (T-18 M3):
// 1. Retire: write aiDemoRetired/{uid} (server-only; `reserve` refuses a
//    retired demo account), read the account again, then delete it in Auth.
//    The usage documents stay, so a failed delete leaves the count as it was.
// 2. Purge, a later run: once the account is gone from Auth and
//    RETIRED_DRAIN_HOURS have passed since it was retired (no ID token of it
//    is still valid, no call of it still running), delete its usage
//    documents and then the retired mark.
// One run is bounded (T-18 M4): at most `maxAccounts` per step, a few at a
// time, and no new work after `budgetMs`; the next run carries on.

/** The part of the Admin Auth API the clean-up uses, so tests can make one call fail. */
export type CleanupAuth = Pick<Auth, 'listUsers' | 'getUser' | 'deleteUser'>;

export interface CleanupOptions {
  /** Accounts each step takes on in one run. */
  maxAccounts?: number;
  /** Accounts handled at the same time. */
  parallel?: number;
  /** Milliseconds after the start of the run after which no new account is taken on. */
  budgetMs?: number;
  /** The clock for the budget; `now` stays the clock for ages. */
  clock?: () => number;
}

export interface CleanupResult {
  /** Anonymous accounts old enough to go that this run listed (at most maxAccounts). */
  found: number;
  /** Accounts deleted in Auth. */
  deleted: number;
  /** Accounts that gained a provider, email or phone after the listing: left alone. */
  skipped: number;
  /** Accounts left for the next run because a step failed. */
  failed: number;
  /** Deleted accounts whose usage documents and retired mark were removed. */
  purged: number;
  /** aiUsageUser documents deleted. */
  usageDocs: number;
  /** Listed accounts or purges not reached because of the cap or the time budget; the next run takes them. */
  remaining: number;
}

const DEFAULTS: Required<CleanupOptions> = {
  maxAccounts: 1000,
  parallel: 10,
  // The function's timeout is 540 s; stop taking work well before it.
  budgetMs: 450_000,
  clock: () => Date.now(),
};

/**
 * An account with no sign-in provider, email or phone: an anonymous one. An
 * account made from a custom token has none of these either and would count;
 * the project mints no custom tokens (T-18 M9), so only the demo's anonymous
 * accounts match.
 */
export function isAnonymous(user: UserRecord): boolean {
  return user.providerData.length === 0 && !user.email && !user.phoneNumber;
}

/** Whether the account was created more than the maximum age before `now`. */
export function isOld(user: UserRecord, now: Date): boolean {
  const created = Date.parse(user.metadata.creationTime);
  // An unreadable creation time is never taken as old.
  return Number.isFinite(created) && now.getTime() - created > ANONYMOUS_MAX_AGE_HOURS * 3_600_000;
}

function isNotFound(error: unknown): boolean {
  return (error as { code?: unknown } | null)?.code === 'auth/user-not-found';
}

/** The account as Auth has it now, or null when it is gone. */
async function currentUser(auth: CleanupAuth, uid: string): Promise<UserRecord | null> {
  try {
    return await auth.getUser(uid);
  } catch (error) {
    if (isNotFound(error)) return null;
    throw error;
  }
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
 * Step 1 for one listed account. The account is read again right before the
 * delete, because it may have gained a provider since the listing (T-18 M2).
 * Limit: Auth has no conditional delete, so an account that links a provider
 * in the few milliseconds between that read and `deleteUser` would still be
 * deleted. In this project only the demo makes anonymous accounts and it never
 * links one to a provider, so that window is not reachable today; a build that
 * links demo accounts would need its own guard (for example linking on the
 * server, which could check the retired mark).
 */
async function retire(
  auth: CleanupAuth,
  db: Firestore,
  uid: string,
  now: Date,
  result: CleanupResult,
): Promise<void> {
  const mark = db.collection(COLLECTIONS.retired).doc(uid);
  // First the mark, so no call of this account counts once the delete starts.
  await mark.set({ retiredAt: now });
  const user = await currentUser(auth, uid);
  if (user !== null && !isAnonymous(user)) {
    await mark.delete();
    result.skipped++;
    return;
  }
  if (user !== null) await auth.deleteUser(uid);
  result.deleted++;
}

/** Step 2 for one retired mark past the drain time; returns whether it was finished. */
async function purge(auth: CleanupAuth, db: Firestore, uid: string, result: CleanupResult): Promise<void> {
  const user = await currentUser(auth, uid);
  const mark = db.collection(COLLECTIONS.retired).doc(uid);
  if (user !== null) {
    // Still in Auth: a failed delete, which step 1 retries (and dates the mark
    // anew); or an account that gained a provider, which is no longer the
    // clean-up's business.
    if (!isAnonymous(user)) await mark.delete();
    return;
  }
  // Usage first, the mark last: a failure leaves the mark for the next run.
  // Awaited first: `result.usageDocs += await ...` would read the total before
  // the await and lose the counts of purges running at the same time.
  const usageDocs = await deleteUsageDocs(db, uid);
  result.usageDocs += usageDocs;
  await mark.delete();
  result.purged++;
}

/** Runs `work` for each item, `parallel` at a time, until the budget runs out; returns how many were not reached. */
async function inChunks<T>(
  items: T[],
  parallel: number,
  outOfTime: () => boolean,
  work: (item: T) => Promise<void>,
  onFailure: () => void,
): Promise<number> {
  for (let i = 0; i < items.length; i += parallel) {
    if (outOfTime()) return items.length - i;
    const settled = await Promise.allSettled(items.slice(i, i + parallel).map(work));
    for (const s of settled) if (s.status === 'rejected') onFailure();
  }
  return 0;
}

/**
 * One clean-up run: first the purge of accounts retired earlier, then the
 * retiring of old anonymous accounts. One account's failure never stops the
 * others; it is counted and the next run retries it.
 */
export async function cleanUpAnonymous(
  auth: CleanupAuth,
  db: Firestore,
  now: Date,
  options: CleanupOptions = {},
): Promise<CleanupResult> {
  const { maxAccounts, parallel, budgetMs, clock } = { ...DEFAULTS, ...options };
  const stopAt = clock() + budgetMs;
  const outOfTime = () => clock() >= stopAt;
  const result: CleanupResult = { found: 0, deleted: 0, skipped: 0, failed: 0, purged: 0, usageDocs: 0, remaining: 0 };
  const failed = () => result.failed++;

  const drained = new Date(now.getTime() - RETIRED_DRAIN_HOURS * 3_600_000);
  const marks = await db.collection(COLLECTIONS.retired).where('retiredAt', '<=', drained).limit(maxAccounts).get();
  result.remaining += await inChunks(
    marks.docs.map((d) => d.id),
    parallel,
    outOfTime,
    (uid) => purge(auth, db, uid, result),
    failed,
  );

  const old: string[] = [];
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (old.length < maxAccounts && isAnonymous(user) && isOld(user, now)) old.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken !== undefined && old.length < maxAccounts && !outOfTime());

  result.found = old.length;
  result.remaining += await inChunks(old, parallel, outOfTime, (uid) => retire(auth, db, uid, now, result), failed);
  return result;
}
