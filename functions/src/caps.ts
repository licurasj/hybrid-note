import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  COLLECTIONS,
  POOLS,
  ceilingMicros,
  type ModelConfig,
  type PoolName,
  type TierLimits,
  type TierName,
} from './config';
import { refuse } from './errors';

// Caps live in server-only documents (D-13): aiUsageUser/{uid}_{day} counts a
// user's requests, aiUsagePool/{pool}_{day} holds a budget pool's spent and
// reserved microdollars. Days are UTC. Every change runs in a transaction, and
// a call reserves its model's ceiling cost before the provider is asked, so
// parallel calls cannot spend past a pool's daily stop.

/** Enough retries for a burst of parallel calls on the same two documents. */
const MAX_ATTEMPTS = 50;

export interface Reservation {
  uid: string;
  day: string;
  pools: PoolName[];
  reservedMicros: number;
}

export function dayOf(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function userRef(db: Firestore, uid: string, day: string) {
  return db.collection(COLLECTIONS.userUsage).doc(`${uid}_${day}`);
}

function poolRef(db: Firestore, pool: PoolName, day: string) {
  return db.collection(COLLECTIONS.poolUsage).doc(`${pool}_${day}`);
}

async function inTransaction<T>(db: Firestore, body: Parameters<Firestore['runTransaction']>[0]): Promise<T> {
  try {
    return (await db.runTransaction(body, { maxAttempts: MAX_ATTEMPTS })) as T;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw refuse('busy', 'the usage counters were too busy, try again');
  }
}

/**
 * Counts one request for the user and reserves the model's ceiling cost in
 * every pool of the tier, or refuses with `dailyCount` / `globalBudget`
 * and changes nothing.
 */
export async function reserve(
  db: Firestore,
  uid: string,
  tier: TierName,
  limits: TierLimits,
  model: ModelConfig,
  now: Date,
): Promise<Reservation> {
  const day = dayOf(now);
  const ceiling = ceilingMicros(model);
  return inTransaction<Reservation>(db, async (tx) => {
    const user = await tx.get(userRef(db, uid, day));
    const pools = await Promise.all(limits.pools.map((pool) => tx.get(poolRef(db, pool, day))));

    if ((user.get('count') ?? 0) >= limits.requestsPerDay) {
      throw refuse('dailyCount', 'daily request limit reached');
    }
    limits.pools.forEach((pool, i) => {
      const used = (pools[i].get('spentMicros') ?? 0) + (pools[i].get('reservedMicros') ?? 0);
      if (used + ceiling > POOLS[pool].usdPerDay * 1e6) {
        throw refuse('globalBudget', 'daily AI budget reached');
      }
    });

    tx.set(
      userRef(db, uid, day),
      { day, tier, count: FieldValue.increment(1), updatedAt: now },
      { merge: true },
    );
    for (const pool of limits.pools) {
      tx.set(
        poolRef(db, pool, day),
        { day, pool, count: FieldValue.increment(1), reservedMicros: FieldValue.increment(ceiling), updatedAt: now },
        { merge: true },
      );
    }
    return { uid, day, pools: limits.pools, reservedMicros: ceiling };
  });
}

/**
 * Counts a request that was refused before any provider call (for example an
 * over-long prompt) against the user's daily count, without a reservation.
 * A user already at the limit stays there.
 */
export async function countOnly(
  db: Firestore,
  uid: string,
  tier: TierName,
  limits: TierLimits,
  now: Date,
): Promise<void> {
  const day = dayOf(now);
  await inTransaction<void>(db, async (tx) => {
    const user = await tx.get(userRef(db, uid, day));
    if ((user.get('count') ?? 0) >= limits.requestsPerDay) return;
    tx.set(
      userRef(db, uid, day),
      { day, tier, count: FieldValue.increment(1), updatedAt: now },
      { merge: true },
    );
  });
}

/**
 * Replaces the reservation with the real cost from the provider's usage. Only
 * increments, so one batch is enough. The real cost is recorded even in the
 * unexpected case that it is above the ceiling, so the stop then holds early.
 */
export async function settle(
  db: Firestore,
  reservation: Reservation,
  actualMicros: number,
  now: Date,
): Promise<void> {
  const batch = db.batch();
  batch.set(
    userRef(db, reservation.uid, reservation.day),
    { spentMicros: FieldValue.increment(actualMicros), updatedAt: now },
    { merge: true },
  );
  for (const pool of reservation.pools) {
    batch.set(
      poolRef(db, pool, reservation.day),
      {
        reservedMicros: FieldValue.increment(-reservation.reservedMicros),
        spentMicros: FieldValue.increment(actualMicros),
        updatedAt: now,
      },
      { merge: true },
    );
  }
  await batch.commit();
}
