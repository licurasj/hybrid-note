// The demo tier's choice and limits (T-18 unit 1) and the clean-up's account
// filter, without emulators.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import type { UserRecord } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';

import { isAnonymous, isOld } from '../src/cleanup';
import { POOLS, TIERS } from '../src/config';
import { resolveTier } from '../src/handler';

/** A Firestore that fails the test on any read: the demo tier needs none. */
const noReads = new Proxy({} as Firestore, {
  get() {
    throw new Error('Firestore was read');
  },
});

/** A Firestore whose allowlist has the given entries. */
function allowlist(entries: Record<string, unknown>): Firestore {
  return {
    collection: (name: string) => {
      assert.equal(name, 'aiAllowlist');
      return { doc: (uid: string) => ({ get: async () => ({ get: (key: string) => (entries[uid] as any)?.[key] }) }) };
    },
  } as unknown as Firestore;
}

describe('resolveTier', () => {
  test('an anonymous account is tier demo, with no allowlist read', async () => {
    assert.equal(await resolveTier(noReads, 'anon', 'anonymous'), 'demo');
  });

  test('other accounts go by the allowlist, whatever their provider', async () => {
    const db = allowlist({ owner: { tier: 'owner' } });
    assert.equal(await resolveTier(db, 'owner', 'google.com'), 'owner');
    assert.equal(await resolveTier(db, 'stranger', 'google.com'), null);
    assert.equal(await resolveTier(db, 'stranger', undefined), null);
    assert.equal(await resolveTier(db, 'stranger', 'password'), null);
  });

  test('an unknown tier on the allowlist is refused', async () => {
    assert.equal(await resolveTier(allowlist({ u: { tier: 'admin' } }), 'u', 'google.com'), null);
  });
});

describe('demo limits (Q-83 A, Q-132 A)', () => {
  test('20 a day, prompt 1,000, context 16,000 bytes, pool global at $0.30', () => {
    assert.equal(TIERS.demo.requestsPerDay, 20);
    assert.equal(TIERS.demo.promptMaxChars, 1000);
    assert.equal(TIERS.demo.contextMaxBytes, 16000);
    assert.deepEqual(TIERS.demo.pools, ['global']);
    assert.equal(POOLS.global.usdPerDay * 1e6, 300_000);
  });

  test('the owner still has no count and no pool (Q-63)', () => {
    assert.equal(TIERS.owner.requestsPerDay, Infinity);
    assert.deepEqual(TIERS.owner.pools, []);
  });
});

function user(fields: Partial<UserRecord> & { creationTime?: string }): UserRecord {
  return {
    uid: 'u',
    providerData: [],
    ...fields,
    metadata: { creationTime: fields.creationTime ?? new Date(0).toUTCString() },
  } as unknown as UserRecord;
}

describe('the clean-up filter', () => {
  const now = new Date('2026-11-17T12:00:00Z');

  test('only an account with no provider, email or phone is anonymous', () => {
    assert.equal(isAnonymous(user({})), true);
    assert.equal(isAnonymous(user({ providerData: [{ providerId: 'google.com' } as any] })), false);
    assert.equal(isAnonymous(user({ email: 'a@example.test' })), false);
    assert.equal(isAnonymous(user({ phoneNumber: '+15555550100' })), false);
  });

  test('old means created more than 24 hours ago; unreadable is never old', () => {
    assert.equal(isOld(user({ creationTime: new Date('2026-11-16T11:59:00Z').toUTCString() }), now), true);
    assert.equal(isOld(user({ creationTime: new Date('2026-11-16T12:01:00Z').toUTCString() }), now), false);
    assert.equal(isOld(user({ creationTime: 'not a date' }), now), false);
  });
});
