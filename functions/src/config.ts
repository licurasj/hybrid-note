// Server-side configuration of aiCommand (T-19). Everything a cap, a limit or
// an App Check decision depends on lives here, so changing a limit or turning
// Android App Check to "enforce" is a function redeploy, never an app release.

/** A caller's tier. T-19 has the owner only; T-18 adds an anonymous demo tier. */
export type TierName = 'owner';

/** A shared daily dollar budget. Every call reserves from each pool of its tier. */
export type PoolName = 'global';

export interface TierLimits {
  /** Requests per user per UTC day, refused and off-topic ones included (Q-29 B). */
  requestsPerDay: number;
  /** Characters in the typed prompt (Proposed 1,000). */
  promptMaxChars: number;
  /** Characters in a `reply` tool's text (Proposed 500). */
  replyMaxChars: number;
  /** UTF-8 bytes of the JSON context (lists summary plus the open list). */
  contextMaxBytes: number;
  /** Lists named in the context. */
  maxLists: number;
  /** Items of the open list sent as context (plan 6.2: about 20). */
  maxItems: number;
  /** Budget pools this tier spends from. */
  pools: PoolName[];
}

export interface PoolLimits {
  /** Hard stop per UTC day in US dollars (D-13, Q-29 B). */
  usdPerDay: number;
}

export const TIERS: Record<TierName, TierLimits> = {
  owner: {
    requestsPerDay: 100,
    promptMaxChars: 1000,
    replyMaxChars: 500,
    contextMaxBytes: 32000,
    maxLists: 100,
    maxItems: 20,
    pools: ['global'],
  },
};

export const POOLS: Record<PoolName, PoolLimits> = {
  global: { usdPerDay: 1 },
};

/** A model and its prices; the per-call ceiling cost is reserved before the call. */
export interface ModelConfig {
  provider: 'fake';
  model: string;
  inputUsdPerMTok: number;
  outputUsdPerMTok: number;
  maxInputTokens: number;
  maxOutputTokens: number;
}

// T-19 unit 3 adds the Claude and DeepSeek entries (Q-28) and their prices.
// The fake model is priced like Claude Haiku 5.5 so the caps behave as they
// will in production.
export const MODELS: Record<string, ModelConfig> = {
  fake: {
    provider: 'fake',
    model: 'fake-model',
    inputUsdPerMTok: 0.1,
    outputUsdPerMTok: 0.5,
    maxInputTokens: 20000,
    maxOutputTokens: 4000,
  },
};

export const ACTIVE_MODEL = 'fake';

/** App Check per app (Q-34 1): "enforce" refuses calls without a valid token. */
export type AppCheckMode = 'enforce' | 'monitor';
export type Platform = 'web' | 'android';

export const APP_CHECK: Record<Platform, { appId: string; mode: AppCheckMode }> = {
  web: { appId: '1:377269928861:web:11348aacadb31b673fe574', mode: 'enforce' },
  android: { appId: '1:377269928861:android:453afa0a586310683fe574', mode: 'monitor' },
};

/** Days a prompt-log document lives before the Firestore TTL policy deletes it (Q-31 B). */
export const PROMPT_LOG_DAYS = 7;

/** Server-only collections: firestore.rules lets no client read or write them. */
export const COLLECTIONS = {
  allowlist: 'aiAllowlist',
  userUsage: 'aiUsageUser',
  poolUsage: 'aiUsagePool',
  promptLog: 'aiPromptLog',
} as const;

/** Microdollars per call that the model can cost at most, from its token ceilings. */
export function ceilingMicros(model: ModelConfig): number {
  return costMicros(model, model.maxInputTokens, model.maxOutputTokens);
}

export function costMicros(model: ModelConfig, inputTokens: number, outputTokens: number): number {
  return Math.ceil(inputTokens * model.inputUsdPerMTok + outputTokens * model.outputUsdPerMTok);
}
