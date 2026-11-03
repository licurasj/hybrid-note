// Shared helpers for tests that need the emulators (`npm test` runs them under
// `firebase emulators:exec`, which sets the *_EMULATOR_HOST variables). Only
// emulator users are created; nothing reaches a real project.
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

export const PROJECT_ID = 'demo-hybrid-note';
const FIRESTORE = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const FUNCTIONS = '127.0.0.1:5001';

process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE;
process.env.GCLOUD_PROJECT = PROJECT_ID;

export function db(): Firestore {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Deletes every document in the emulator's database for this project. */
export async function clearFirestore(): Promise<void> {
  const response = await fetch(
    `http://${FIRESTORE}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!response.ok) throw new Error(`clearing Firestore failed: ${response.status}`);
}

export interface EmulatorUser {
  uid: string;
  idToken: string;
}

let userCount = 0;

/** Signs up a new Auth emulator user and returns its id token. */
export async function newUser(): Promise<EmulatorUser> {
  userCount++;
  const response = await fetch(
    `http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: `user${userCount}-${Date.now()}@example.test`,
        password: 'emulator-only',
        returnSecureToken: true,
      }),
    },
  );
  const body = (await response.json()) as { localId: string; idToken: string };
  if (!response.ok) throw new Error(`sign-up failed: ${JSON.stringify(body)}`);
  return { uid: body.localId, idToken: body.idToken };
}

export async function allow(uid: string, tier = 'owner'): Promise<void> {
  await db().collection('aiAllowlist').doc(uid).set({ tier });
}

export interface CallResult {
  ok: boolean;
  result?: any;
  status?: string;
  reason?: string;
}

/** Calls aiCommand in the Functions emulator through the callable protocol. */
export async function callAi(
  data: unknown,
  options: { idToken?: string; appCheckToken?: string } = {},
): Promise<CallResult> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (options.idToken) headers.Authorization = `Bearer ${options.idToken}`;
  if (options.appCheckToken) headers['X-Firebase-AppCheck'] = options.appCheckToken;
  const response = await fetch(`http://${FUNCTIONS}/${PROJECT_ID}/us-central1/aiCommand`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as any;
  if (body.error) {
    return { ok: false, status: body.error.status, reason: body.error.details?.reason };
  }
  return { ok: true, result: body.result };
}

export const GROCERY = 'grocery';
export const TODO = 'todo';

/** A request from Android (App Check on "monitor") with the Grocery list open. */
export function request(prompt: string, extra: Record<string, unknown> = {}) {
  return {
    prompt,
    platform: 'android',
    locale: 'en',
    lists: [
      { id: GROCERY, name: 'Grocery', fields: [{ key: 'name', type: 'text' }], aiAllowed: true },
      { id: TODO, name: 'To do', fields: [{ key: 'title', type: 'text' }], aiAllowed: true },
    ],
    openList: {
      definition: { id: GROCERY, name: 'Grocery', aiAllowed: true, fields: [{ key: 'name', type: 'text' }] },
      items: [{ id: 'i1', values: { name: 'bread' } }],
    },
    ...extra,
  };
}
