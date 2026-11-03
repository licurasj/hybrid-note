import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { decideAppCheck } from './appCheck';
import { countOnly, reserve, settle, type Reservation } from './caps';
import { ACTIVE_MODEL, COLLECTIONS, MODELS, TIERS, costMicros, type ModelConfig, type TierName } from './config';
import { reasonOf, refuse } from './errors';
import { uidHash, type LogSink, type RequestMeta } from './log';
import { filterOutput, structuralCheck, type DeclineReason, type SchemaCheck, type ToolCall } from './output';
import { writePromptLog } from './promptLog';
import type { AiProvider, ProviderResponse } from './provider/types';
import { parseRequest } from './request';

// Placeholder: T-19 unit 3 writes the real system prompt (list design, the
// off-topic rule, routing between lists) next to the tool schemas.
export const SYSTEM_PROMPT =
  'You help with the user\'s lists in Hybrid Note only. Act through the tools. ' +
  'For anything not about the user\'s lists, call decline.';

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
  schemaCheck?: SchemaCheck;
}

export interface AiResponse {
  requestId: string;
  outcome: 'ok' | 'declined';
  toolCalls: ToolCall[];
  declineReason?: DeclineReason;
  usage: { inputTokens: number; outputTokens: number; costUsd: number };
}

/** Finds the caller's tier on the server-only allowlist; T-18 adds the demo tier here. */
export async function resolveTier(db: Firestore, uid: string): Promise<TierName | null> {
  const entry = await db.collection(COLLECTIONS.allowlist).doc(uid).get();
  const tier = entry.get('tier');
  return typeof tier === 'string' && Object.hasOwn(TIERS, tier) ? (tier as TierName) : null;
}

/**
 * aiCommand's whole flow, in order: sign-in, App Check, allowlist tier, input
 * limits, prompt log, cap reservation, provider call, settlement, output
 * filter. The function never writes list data: the client validates,
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

    let response: ProviderResponse;
    try {
      response = await deps.provider.call({ model, system: SYSTEM_PROMPT, request });
    } catch {
      // The usage of a failed call is unknown, so the ceiling stays spent.
      await settle(deps.db, reservation, reservation.reservedMicros, deps.now());
      throw refuse('provider', 'the AI provider failed');
    }
    const cost = costMicros(model, response.usage.inputTokens, response.usage.outputTokens);
    await settle(deps.db, reservation, cost, deps.now());
    meta.inputTokens = response.usage.inputTokens;
    meta.outputTokens = response.usage.outputTokens;
    meta.costMicros = cost;
    meta.stopReason = response.stopReason;

    const output = filterOutput(response, request, limits, deps.schemaCheck ?? structuralCheck);
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
      usage: {
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        costUsd: cost / 1e6,
      },
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
