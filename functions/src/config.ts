// Server-side configuration of aiCommand (T-19). Everything a cap, a limit or
// an App Check decision depends on lives here, so changing a limit or turning
// Android App Check to "enforce" is a function redeploy, never an app release.

/** A caller's tier: `owner` from the allowlist, `demo` for anonymous portfolio visitors (T-18). */
export type TierName = 'owner' | 'demo';

/** A shared daily dollar budget. Every call reserves from each pool of its tier. */
export type PoolName = 'global';

export interface TierLimits {
  /** Requests per user per UTC day, refused and off-topic ones included; Infinity for no limit (Q-63). */
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
  /** Budget pools this tier spends from; none means no daily dollar stop (Q-63). */
  pools: PoolName[];
}

export interface PoolLimits {
  /** Hard stop per UTC day in US dollars (D-13, Q-29 B). */
  usdPerDay: number;
}

export const TIERS: Record<TierName, TierLimits> = {
  // No daily count and no pool (Q-63): the provider spend limits are the stops
  // left, and aiUsageUser still records the day's count and spend.
  owner: {
    requestsPerDay: Infinity,
    promptMaxChars: 1000,
    replyMaxChars: 500,
    contextMaxBytes: 32000,
    maxLists: 100,
    maxItems: 20,
    pools: [],
  },
  // The portfolio demo (T-18, Q-83 A): every anonymous visitor, by the verified
  // token's sign-in provider, never the allowlist. The daily count is a soft
  // guard per visitor (a new anonymous account starts at 0); the pool is the
  // real stop. Prompt 1,000 as the prompt bar (Q-132). Context: the largest
  // starter-list request measured 10,949 bytes (Tasks open with 20 filled
  // sample items, T-18 unit 1, 2026-11-17); 16,000 leaves room for an English
  // follow-up and a few lists of the visitor's own.
  demo: {
    requestsPerDay: 20,
    promptMaxChars: 1000,
    replyMaxChars: 500,
    contextMaxBytes: 16000,
    maxLists: 100,
    maxItems: 20,
    pools: ['global'],
  },
};

export const POOLS: Record<PoolName, PoolLimits> = {
  // Holds only the demo's spend since Q-63; $0.30 per UTC day (Q-83 A).
  global: { usdPerDay: 0.3 },
};

/** US dollars per million tokens. `cacheWrite` is the 5-minute cache write; no premium means = input. */
export interface Prices {
  inputUsdPerMTok: number;
  outputUsdPerMTok: number;
  cacheReadUsdPerMTok: number;
  cacheWriteUsdPerMTok: number;
}

/**
 * A model, its prices and limits. The per-request ceiling cost is reserved
 * before the call (D-13), so prices and token ceilings must be the provider's
 * real ones. Sources: the claude-api skill (Claude, cached 2026-10-06),
 * api-docs.deepseek.com/quick_start/pricing (DeepSeek, read 2026-11-03) and
 * developers.openai.com/api/docs/pricing (OpenAI, read 2026-11-03).
 */
export interface ModelConfig {
  provider: 'fake' | 'claude' | 'deepseek' | 'openai';
  model: string;
  prices: Prices;
  /**
   * Higher prices in fixed UTC hours on weekdays (DeepSeek's peak). Chinese
   * public holidays, which DeepSeek bills off-peak, are billed here at peak,
   * and aiCommand prices a request at the dearer of its start and end time
   * (handler.ts runCost): the counters may overstate a cost, not understate
   * it, unless DeepSeek prices one request in two parts.
   */
  peak?: { prices: Prices; utcHours: [number, number][] };
  /** Input tokens one call can have: the stable prefix plus the largest context the tier allows. */
  maxInputTokens: number;
  /** The call's max_tokens; thinking counts against it. */
  maxOutputTokens: number;
  /** Claude: output_config.effort. DeepSeek: reasoning_effort. */
  effort?: 'low' | 'medium' | 'high';
  /**
   * Tools sent in their strict variant (schema/ai_tools.strict.json); the
   * others go as full schemas, checked here (schemas.ts) with one retry.
   */
  strictTools: readonly string[];
}

/** Provider calls per request: the first one plus one schema self-correction (Q-34 A). */
export const MAX_ATTEMPTS = 2;

const HAIKU_5_5: Prices = {
  // Up to 100K prompt tokens; maxInputTokens keeps every call under that rate card.
  inputUsdPerMTok: 0.1,
  outputUsdPerMTok: 0.5,
  cacheReadUsdPerMTok: 0.01,
  cacheWriteUsdPerMTok: 0.125,
};

// Claude compiles all strict tools into one grammar and refuses ours as too
// large with create_list and patch_list in it (400 "The compiled grammar is
// too large", measured 2026-11-03); the five small tools stay strict.
const CLAUDE_STRICT = ['upsert_items', 'delete_items', 'choose_list', 'reply', 'decline'];

// Q-28: Claude Haiku 5.5 and DeepSeek V4.1 Flash are evaluated side by side
// (T-19 unit 3); Claude Sonnet 5.5 is the fallback by config. The fake model is
// priced and sized like Haiku 5.5 so the caps behave as they will in production.
export const MODELS: Record<string, ModelConfig> = {
  fake: {
    provider: 'fake',
    model: 'fake-model',
    prices: HAIKU_5_5,
    maxInputTokens: 70000,
    maxOutputTokens: 8000,
    strictTools: CLAUDE_STRICT,
  },
  'claude-haiku-5-5': {
    provider: 'claude',
    model: 'claude-haiku-5-5',
    prices: HAIKU_5_5,
    maxInputTokens: 70000,
    maxOutputTokens: 8000,
    effort: 'medium',
    strictTools: CLAUDE_STRICT,
  },
  'claude-sonnet-5-5': {
    provider: 'claude',
    model: 'claude-sonnet-5-5',
    prices: { inputUsdPerMTok: 2, outputUsdPerMTok: 10, cacheReadUsdPerMTok: 0.2, cacheWriteUsdPerMTok: 2.5 },
    maxInputTokens: 70000,
    maxOutputTokens: 8000,
    effort: 'medium',
    strictTools: CLAUDE_STRICT,
  },
  'deepseek-flash': {
    provider: 'deepseek',
    model: 'deepseek-flash',
    // Off-peak; DeepSeek has no cache write premium.
    prices: { inputUsdPerMTok: 0.15, outputUsdPerMTok: 0.6, cacheReadUsdPerMTok: 0.003, cacheWriteUsdPerMTok: 0.15 },
    peak: {
      prices: { inputUsdPerMTok: 0.3, outputUsdPerMTok: 1.2, cacheReadUsdPerMTok: 0.006, cacheWriteUsdPerMTok: 0.3 },
      // 01:00-04:00 and 06:00-10:00 UTC, Monday to Friday.
      utcHours: [
        [1, 4],
        [6, 10],
      ],
    },
    maxInputTokens: 70000,
    maxOutputTokens: 8000,
    effort: 'high',
    // DeepSeek's strict mode (beta) needs every property required; the
    // schemas have optional ones, so DeepSeek gets the full schemas, checked here.
    strictTools: [],
  },
  // OpenAI's cheapest current model (W1: a later option, not evaluated yet).
  'gpt-6-luna': {
    provider: 'openai',
    model: 'gpt-6-luna',
    // Standard tier, global processing, prompts under 272K tokens (2x above);
    // cache write is the 30-minute rate. Regional (data residency) endpoints
    // cost 10 % more: keep the project on global processing, or raise these
    // prices first, or the ceiling understates (N7).
    prices: { inputUsdPerMTok: 0.1, outputUsdPerMTok: 0.5, cacheReadUsdPerMTok: 0.01, cacheWriteUsdPerMTok: 0.125 },
    maxInputTokens: 70000,
    maxOutputTokens: 8000,
    effort: 'medium',
    // Strict mode needs every property required, as at DeepSeek.
    strictTools: [],
  },
};

/**
 * The model aiCommand uses outside the emulator: DeepSeek V4.1 Flash, the
 * owner's pick after the T-19 unit 3 eval (Q-28, 2026-11-03). Claude Haiku 5.5
 * stays the backup: switching is this line and a redeploy (both secrets are
 * bound to the function).
 */
export const ACTIVE_MODEL = 'deepseek-flash';

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
  /** Anonymous accounts the clean-up job is removing; `reserve` refuses them (T-18 M3). */
  retired: 'aiDemoRetired',
} as const;

/** Anonymous Auth accounts older than this are deleted with their usage documents (T-18 clean-up). */
export const ANONYMOUS_MAX_AGE_HOURS = 24;

/**
 * Hours a deleted anonymous account's usage documents stay before the
 * clean-up removes them: an ID token lives up to 1 hour after the account is
 * gone (the callable framework does not check revocation) and a call up to
 * 120 s, so after 2 hours no request of that account can still count or
 * settle (T-18 M3).
 */
export const RETIRED_DRAIN_HOURS = 2;

/** Token counts of one or more provider calls. `inputTokens` excludes cache reads and writes. */
export interface Usage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

export const NO_USAGE: Usage = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };

export function addUsage(a: Usage, b: Usage): Usage {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens,
    cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens,
  };
}

/** The prices in effect at `at` (peak hours are weekday UTC hours). */
export function pricesAt(model: ModelConfig, at: Date): Prices {
  const peak = model.peak;
  if (peak === undefined) return model.prices;
  const day = at.getUTCDay();
  const hour = at.getUTCHours();
  const weekday = day >= 1 && day <= 5;
  return weekday && peak.utcHours.some(([from, to]) => hour >= from && hour < to) ? peak.prices : model.prices;
}

/** The highest prices the model can be billed at. */
function worstPrices(model: ModelConfig): Prices {
  return model.peak?.prices ?? model.prices;
}

/**
 * Microdollars a request can cost at most: every attempt at its token
 * ceilings, all input billed at the dearer of the input and cache-write rate.
 */
export function ceilingMicros(model: ModelConfig): number {
  const p = worstPrices(model);
  const perCall =
    model.maxInputTokens * Math.max(p.inputUsdPerMTok, p.cacheWriteUsdPerMTok) + model.maxOutputTokens * p.outputUsdPerMTok;
  return Math.ceil(MAX_ATTEMPTS * perCall);
}

/** Microdollars the given usage costs at the prices in effect at `at`. */
export function costMicros(model: ModelConfig, usage: Usage, at: Date): number {
  const p = pricesAt(model, at);
  return Math.ceil(
    usage.inputTokens * p.inputUsdPerMTok +
      usage.outputTokens * p.outputUsdPerMTok +
      usage.cacheReadTokens * p.cacheReadUsdPerMTok +
      usage.cacheWriteTokens * p.cacheWriteUsdPerMTok,
  );
}
