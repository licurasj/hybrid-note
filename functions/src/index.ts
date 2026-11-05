import { randomUUID } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { onCall } from 'firebase-functions/v2/https';

import { ACTIVE_MODEL, MODELS, type ModelConfig } from './config';
import { refuse } from './errors';
import { handleAiCommand } from './handler';
import { cloudLogSink } from './log';
import { ClaudeProvider } from './provider/claude';
import { DeepSeekProvider } from './provider/deepseek';
import { FakeProvider } from './provider/fake';
import { OpenAiProvider } from './provider/openai';
import { ProviderError, type AiProvider } from './provider/types';

initializeApp();

// One Secret Manager secret per provider (Q-28). The owner sets them with
// `firebase functions:secrets:set` (T-19 unit 6); on the emulator they come
// from the git-ignored functions/.secret.local.
const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
const deepseekKey = defineSecret('DEEPSEEK_API_KEY');
const openaiKey = defineSecret('OPENAI_API_KEY');

/**
 * The model of this call. The emulator always uses the fake provider, so
 * tests never reach a real API or spend money, even when the owner has put
 * keys in .secret.local; AI_REAL_PROVIDER=true in the shell that starts the
 * emulator opts in to the configured model.
 */
function pickModel(): ModelConfig {
  const emulator = process.env.FUNCTIONS_EMULATOR === 'true';
  return emulator && process.env.AI_REAL_PROVIDER !== 'true' ? MODELS.fake : MODELS[ACTIVE_MODEL];
}

/** The adapter for the model; read only after the checks before the provider call passed. */
function providerFor(model: ModelConfig): AiProvider {
  try {
    switch (model.provider) {
      case 'fake':
        return new FakeProvider();
      case 'claude':
        return new ClaudeProvider(anthropicKey.value());
      case 'deepseek':
        return new DeepSeekProvider(deepseekKey.value());
      case 'openai':
        return new OpenAiProvider(openaiKey.value());
    }
  } catch (error) {
    if (!(error instanceof ProviderError)) throw error;
  }
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
    // Callables are reached with a Firebase ID token, not a Google IAM one, so
    // Cloud Run must let every caller in; handleAiCommand does the checks.
    // Declared here so every deploy keeps it (the first create failed before
    // the CLI set it, T-19 unit 6).
    invoker: 'public',
    maxInstances: 2,
    // runModel's deadline is 100 s for every provider call together; the rest settles and logs.
    timeoutSeconds: 120,
    secrets: [anthropicKey, deepseekKey, openaiKey],
    memory: '256MiB',
  },
  (request) => {
    const model = pickModel();
    return handleAiCommand(
      {
        uid: request.auth?.uid,
        verifiedAppId: request.app?.appId,
        appCheckTokenPresent: Boolean(request.rawRequest.header('X-Firebase-AppCheck')),
        data: request.data,
      },
      {
        db: getFirestore(),
        get provider() {
          return providerFor(model);
        },
        model,
        log: cloudLogSink,
        now: () => new Date(),
        newRequestId: randomUUID,
      },
    );
  },
);
