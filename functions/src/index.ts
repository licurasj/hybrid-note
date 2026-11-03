import { randomUUID } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { ACTIVE_MODEL, MODELS } from './config';
import { refuse } from './errors';
import { handleAiCommand } from './handler';
import { cloudLogSink } from './log';
import { FakeProvider } from './provider/fake';
import type { AiProvider } from './provider/types';

initializeApp();

/** The configured provider. The fake one answers only inside the emulator. */
function provider(): AiProvider {
  const model = MODELS[ACTIVE_MODEL];
  if (model.provider === 'fake' && process.env.FUNCTIONS_EMULATOR === 'true') {
    return new FakeProvider();
  }
  // T-19 unit 3 adds the Claude and DeepSeek adapters here.
  throw refuse('provider', 'no AI provider is configured');
}

/**
 * The AI callable (T-19, Q-33 A us-central1). App Check enforcement by the
 * framework is off: handleAiCommand applies the per-app setting itself
 * (Q-34 1), using the app id the framework verified.
 */
export const aiCommand = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: false,
    maxInstances: 2,
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  (request) =>
    handleAiCommand(
      {
        uid: request.auth?.uid,
        verifiedAppId: request.app?.appId,
        appCheckTokenPresent: Boolean(request.rawRequest.header('X-Firebase-AppCheck')),
        data: request.data,
      },
      {
        db: getFirestore(),
        get provider() {
          return provider();
        },
        log: cloudLogSink,
        now: () => new Date(),
        newRequestId: randomUUID,
      },
    ),
);
