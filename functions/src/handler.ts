import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { decideAppCheck } from './appCheck';
import { countOnly, reserve, settle, type Reservation } from './caps';
import {
  ACTIVE_MODEL,
  COLLECTIONS,
  MODELS,
  TIERS,
  MAX_ATTEMPTS,
  addUsage,
  ceilingMicros,
  costMicros,
  type ModelConfig,
  type TierName,
  type Usage,
} from './config';
import { reasonOf, refuse } from './errors';
import { uidHash, type LogSink, type RequestMeta } from './log';
import { filterOutput, retryFeedback, type DeclineReason, type SchemaCheck, type ToolCall } from './output';
import { writePromptLog } from './promptLog';
import { buildUserMessage, systemPrompt } from './prompt';
import {
  ProviderError,
  TOOL_NAMES,
  type AiProvider,
  type ProviderCall,
  type ProviderResponse,
  type ToolName,
} from './provider/types';
import { parseRequest, type AiRequest } from './request';
import { loadTools, schemaErrors } from './schemas';

export interface CallInput {
  uid?: string;
  /** `request.app.appId`: present only when the framework verified the token. */
  verifiedAppId?: string;
  appCheckTokenPresent: boolean;
  data: unknown;
}

export interface Deps {
  db: Firestore;
  provider: AiProvider;
  log: LogSink;
  now: () => Date;
  newRequestId: () => string;
  model?: ModelConfig;
  /** The tool-call check; the unit 1 JSON Schemas (schemaErrors) by default. */
  schemaCheck?: SchemaCheck;
  /** Clock and wait for runModel, for tests. */
  runOptions?: RunOptions;
}

export interface AiResponse {
  requestId: string;
  outcome: 'ok' | 'declined';
  toolCalls: ToolCall[];
  declineReason?: DeclineReason;
  usage: {
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens: number;
    cacheWriteTokens: number;
    costUsd: number;
  };
}

/** The whole provider step's time; aiCommand's 120 s timeout leaves the rest to settle and log. */
export const PROVIDER_DEADLINE_MS = 100_000;
/** One provider call's time at most. */
export const CALL_TIMEOUT_MS = 50_000;
/** A retry or the self-correction call starts only with this much time left. */
export const MIN_ATTEMPT_MS = 20_000;

/**
 * Whether a failed call cannot have been billed: the provider answered with
 * an error status before generating anything. A timeout, a dropped
 * connection or an unreadable answer may have been billed.
 */
export function unbilled(error: unknown): boolean {
  if (!(error instanceof ProviderError)) return false;
  switch (error.kind) {
    case 'auth':
    case 'billing':
    case 'rateLimit':
    case 'badRequest':
    case 'noKey':
      return true;
    case 'overloaded':
      return error.status !== undefined && !SLOW_FAILURES.has(error.status);
    default:
      return false;
  }
}

/**
 * Gateway timeouts: the answer came after a long wait, maybe after the model
 * generated (and billed) output, so they count as possibly billed and are not
 * retried (L15 of the unit 5 follow-up review). Other 5xx answers are fast
 * refusals: unbilled, retried once.
 */
const SLOW_FAILURES = new Set([504, 524]);

/** Errors worth one more try: "busy, try again" answers, which cost nothing. */
function transient(error: unknown): boolean {
  return error instanceof ProviderError && (error.kind === 'rateLimit' || (error.kind === 'overloaded' && unbilled(error)));
}

export interface ModelRun {
  response: ProviderResponse;
  usage: Usage;
  attempts: number;
  /**
   * Why the first answer was used although the self-correction ran or should
   * have: its error kind, noTime, or the second answer's flaw (length,
   * refusal, fewerCalls).
   */
  retryError?: string;
  /** The failed self-correction call may have been billed (cost unknown). */
  retryMaybeBilled?: boolean;
}

export interface RunOptions {
  onAttempt?: (attempts: number) => void;
  clock?: () => number;
  wait?: (ms: number) => Promise<void>;
}

/**
 * The provider step shared by aiCommand and the eval (eval/run.ts): one call,
 * then one self-correction call when a known tool's arguments fail the
 * schema (Q-34 A). The whole step has one deadline (M2 of the unit 5 review):
 * each call gets the time left (at most CALL_TIMEOUT_MS), a busy answer is
 * retried once when time allows, and the self-correction runs only with
 * MIN_ATTEMPT_MS left. When the self-correction fails, the first answer is
 * used (its invalid calls are dropped by filterOutput) instead of failing
 * the request (M3).
 */
export async function runModel(
  provider: AiProvider,
  model: ModelConfig,
  request: AiRequest,
  schemaCheck: SchemaCheck,
  now: Date,
  options: RunOptions = {},
): Promise<ModelRun> {
  const clock = options.clock ?? Date.now;
  const wait = options.wait ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const deadline = clock() + PROVIDER_DEADLINE_MS;
  const left = () => deadline - clock();
  const attempt = async (call: ProviderCall): Promise<ProviderResponse> => {
    try {
      return await provider.call({ ...call, timeoutMs: Math.min(CALL_TIMEOUT_MS, left()) });
    } catch (error) {
      if (!transient(error) || left() < MIN_ATTEMPT_MS + 1000) throw error;
      await wait(1000);
      return provider.call({ ...call, timeoutMs: Math.min(CALL_TIMEOUT_MS, left()) });
    }
  };
  const call: ProviderCall = {
    model,
    system: systemPrompt(),
    tools: loadTools(model.strictTools),
    user: buildUserMessage(request, now),
    request,
  };
  options.onAttempt?.(1);
  const first = await attempt(call);
  const feedback = first.stopReason === 'end' ? retryFeedback(first, schemaCheck) : [];
  if (feedback.length === 0) return { response: first, usage: first.usage, attempts: 1 };
  if (left() < MIN_ATTEMPT_MS) return { response: first, usage: first.usage, attempts: 1, retryError: 'noTime' };
  options.onAttempt?.(2);
  let second: ProviderResponse;
  try {
    second = await attempt({ ...call, retry: { previous: first, feedback } });
  } catch (error) {
    return {
      response: first,
      usage: first.usage,
      attempts: 2,
      retryError: error instanceof ProviderError ? error.kind : 'unknown',
      retryMaybeBilled: !unbilled(error),
    };
  }
  // The second answer replaces the first only when it is complete and keeps at
  // least as many valid calls (L14 of the unit 5 follow-up review); both are paid.
  const usage = addUsage(first.usage, second.usage);
  const validFirst = knownCalls(first) - feedback.length;
  const flaw =
    second.stopReason !== 'end' ? second.stopReason : validCalls(second, schemaCheck) < validFirst ? 'fewerCalls' : undefined;
  if (flaw !== undefined) return { response: first, usage, attempts: 2, retryError: flaw };
  return { response: second, usage, attempts: 2 };
}

/** Calls to the known tools in an answer. */
function knownCalls(response: ProviderResponse): number {
  return response.content.filter((b) => b.type === 'tool_call' && (TOOL_NAMES as readonly string[]).includes(b.name)).length;
}

/** Calls to the known tools whose arguments pass the schema check. */
function validCalls(response: ProviderResponse, schemaCheck: SchemaCheck): number {
  return response.content.filter(
    (b) =>
      b.type === 'tool_call' &&
      (TOOL_NAMES as readonly string[]).includes(b.name) &&
      schemaCheck(b.name as ToolName, b.args).length === 0,
  ).length;
}

/** Finds the caller's tier on the server-only allowlist; T-18 adds the demo tier here. */
export async function resolveTier(db: Firestore, uid: string): Promise<TierName | null> {
  const entry = await db.collection(COLLECTIONS.allowlist).doc(uid).get();
  const tier = entry.get('tier');
  return typeof tier === 'string' && Object.hasOwn(TIERS, tier) ? (tier as TierName) : null;
}

/**
 * aiCommand's whole flow, in order: sign-in, App Check, allowlist tier, input
 * limits, prompt log, cap reservation, provider call (with one schema
 * self-correction), settlement, output filter. The function never writes list data: the client validates,
 * previews and applies the returned tool calls (plan 7.1 step 5).
 */
export async function handleAiCommand(input: CallInput, deps: Deps): Promise<AiResponse> {
  const started = deps.now();
  const meta: RequestMeta = { requestId: deps.newRequestId() };
  const model = deps.model ?? MODELS[ACTIVE_MODEL];
  try {
    const uid = input.uid;
    if (uid === undefined) throw refuse('signIn', 'sign-in required');
    meta.uidHash = uidHash(uid);

    const appCheck = decideAppCheck({
      verifiedAppId: input.verifiedAppId,
      tokenPresent: input.appCheckTokenPresent,
      declaredPlatform: (input.data as { platform?: unknown } | null)?.platform,
    });
    meta.appCheck = { verdict: appCheck.verdict, platform: appCheck.platform, mode: appCheck.mode };
    if (!appCheck.allow) throw refuse('appCheck', 'App Check token missing or invalid');

    const tier = await resolveTier(deps.db, uid);
    if (tier === null) throw refuse('notAllowed', 'this account may not use AI');
    meta.tier = tier;
    const limits = TIERS[tier];

    let request;
    try {
      request = parseRequest(input.data, limits);
    } catch (error) {
      await countOnly(deps.db, uid, tier, limits, started);
      throw error;
    }
    meta.hasOpenList = request.openList !== null;
    meta.listCount = request.lists.length;
    meta.itemCount = request.openList?.items.length ?? 0;
    meta.promptChars = [...request.prompt].length;

    await writePromptLog(deps.db, {
      requestId: meta.requestId,
      uidHash: meta.uidHash,
      prompt: request.prompt,
      now: started,
    });

    meta.provider = deps.provider.name;
    meta.model = model.model;
    const reservation: Reservation = await reserve(deps.db, uid, tier, limits, model, started);

    const schemaCheck = deps.schemaCheck ?? schemaErrors;
    let run: ModelRun;
    try {
      run = await runModel(deps.provider, model, request, schemaCheck, started, {
        onAttempt: (n) => (meta.attempts = n),
        ...deps.runOptions,
      });
    } catch (error) {
      // An error answer was not billed; otherwise the usage is unknown and the
      // ceiling stays spent (M1 of the unit 5 review).
      meta.providerError = error instanceof ProviderError ? error.kind : 'unknown';
      await settle(deps.db, reservation, unbilled(error) ? 0 : reservation.reservedMicros, deps.now());
      throw refuse('provider', 'the AI provider failed');
    }
    const { response, usage } = run;
    meta.retryError = run.retryError;
    // A failed self-correction that may have been billed counts as one call at its ceiling.
    const cost =
      costMicros(model, usage, started) + (run.retryMaybeBilled ? Math.ceil(ceilingMicros(model) / MAX_ATTEMPTS) : 0);
    await settle(deps.db, reservation, cost, deps.now());
    meta.inputTokens = usage.inputTokens;
    meta.outputTokens = usage.outputTokens;
    meta.cacheReadTokens = usage.cacheReadTokens;
    meta.cacheWriteTokens = usage.cacheWriteTokens;
    meta.costMicros = cost;
    meta.stopReason = response.stopReason;
    // A cut answer may end in a half tool call: none of it is used.
    if (response.stopReason === 'length') throw refuse('outputTooLong', 'the AI answer was cut at its length limit');

    const output = filterOutput(response, request, limits, schemaCheck);
    meta.outcome = output.outcome;
    meta.reason = output.declineReason;
    meta.droppedText = output.droppedText;
    meta.droppedTools = output.droppedTools;
    meta.replyTruncated = output.replyTruncated;
    meta.toolCounts = {};
    for (const call of output.toolCalls) {
      meta.toolCounts[call.name] = (meta.toolCounts[call.name] ?? 0) + 1;
    }

    return {
      requestId: meta.requestId,
      outcome: output.outcome,
      toolCalls: output.toolCalls,
      ...(output.declineReason ? { declineReason: output.declineReason } : {}),
      usage: { ...usage, costUsd: cost / 1e6 },
    };
  } catch (error) {
    meta.reason = reasonOf(error);
    meta.outcome = meta.reason === 'internal' ? 'error' : 'refused';
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', 'internal error');
  } finally {
    meta.latencyMs = deps.now().getTime() - started.getTime();
    deps.log('aiCommand', meta);
  }
}
