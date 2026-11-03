// T-19 unit 2: aiCommand's server-only collections (the allowlist, the cap
// counters and the 7-day prompt log) are closed to every client, signed in or
// not, the owner of the counted uid included. Run with the rules suite (see
// rules.test.js). A project id of its own keeps this file's data apart from
// rules.test.js when node:test runs both files at once.
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  setLogLevel,
  updateDoc,
} from 'firebase/firestore';

const OWNER = 'owner-uid';
const DAY = '2026-11-03';

// One existing document per collection, as aiCommand writes them.
const DOCS = {
  [`aiAllowlist/${OWNER}`]: { tier: 'owner' },
  [`aiUsageUser/${OWNER}_${DAY}`]: { day: DAY, tier: 'owner', count: 3, spentMicros: 900 },
  [`aiUsagePool/global_${DAY}`]: { day: DAY, pool: 'global', count: 3, reservedMicros: 0, spentMicros: 900 },
  'aiPromptLog/req-1': { requestId: 'req-1', uidHash: 'abc', prompt: 'add milk' },
};

let env;

before(async () => {
  setLogLevel('silent');
  env = await initializeTestEnvironment({
    projectId: 'demo-ai-server-only',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [path, data] of Object.entries(DOCS)) {
      await setDoc(doc(db, path), data);
    }
  });
});

const clients = {
  'the owner': () => env.authenticatedContext(OWNER).firestore(),
  'another user': () => env.authenticatedContext('other-uid').firestore(),
  'a signed-out client': () => env.unauthenticatedContext().firestore(),
};

for (const [who, open] of Object.entries(clients)) {
  describe(`${who} is denied`, () => {
    for (const path of Object.keys(DOCS)) {
      const [name] = path.split('/');

      test(`reading ${name}`, async () => {
        const db = open();
        await assertFails(getDoc(doc(db, path)));
        await assertFails(getDocs(collection(db, name)));
      });

      test(`writing ${name}`, async () => {
        const db = open();
        await assertFails(setDoc(doc(db, `${name}/new-doc`), { tier: 'owner', count: 0 }));
        await assertFails(updateDoc(doc(db, path), { count: 0, tier: 'owner' }));
        await assertFails(deleteDoc(doc(db, path)));
      });
    }
  });
}
