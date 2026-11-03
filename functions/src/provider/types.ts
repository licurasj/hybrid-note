import type { ModelConfig, Usage } from '../config';
import type { AiRequest } from '../request';

/** The tools the model may call (Q-32 A plus, Q-36). Unit 1 owns their schemas. */
export const TOOL_NAMES = [
  'create_list',
  'patch_list',
  'upsert_items',
  'delete_items',
  'choose_list',
  'reply',
  'decline',
] as const;
export type ToolName = (typeof TOOL_NAMES)[number];

/** One tool definition in Claude's shape, as schema/ai_tools.*.json hold them. */
export interface ToolDef {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  strict?: boolean;
}

export type ContentBlock =
  | { type: 'text'; text: string }
  /** `args` is undefined when the provider sent arguments that are not JSON. */
  | { type: 'tool_call'; id: string; name: string; args: unknown };

export interface ProviderResponse {
  content: ContentBlock[];
  usage: Usage;
  /** `refusal`: the provider's own safety stop; `length`: cut at the output ceiling. */
  stopReason: 'end' | 'refusal' | 'length';
  /** The assistant turn in the provider's own format, sent back on a retry. */
  raw?: unknown;
}

/** What one rejected tool call of the previous answer got wrong, for the retry. */
export interface ToolFeedback {
  id: string;
  errors: string[];
}

export interface ProviderCall {
  model: ModelConfig;
  /** Stable for every request (cacheable): rules and example designs. */
  system: string;
  /** Stable for every request (cacheable), in a fixed order. */
  tools: ToolDef[];
  /** The request's context and prompt (prompt.ts). */
  user: string;
  request: AiRequest;
  /** The most this call may take (runModel's deadline); the adapter's own default otherwise. */
  timeoutMs?: number;
  /** Set on the one self-correction call: the previous answer and what failed. */
  retry?: { previous: ProviderResponse; feedback: ToolFeedback[] };
}

/**
 * Why a provider call failed, by kind, so the metadata log and the client can
 * tell them apart. Refusals and length cuts are not errors: they come back as
 * `stopReason`.
 */
export type ProviderErrorKind =
  | 'auth' // 401/403: bad or missing key
  | 'billing' // 402 or a billing error: no credit left
  | 'rateLimit' // 429
  | 'overloaded' // 5xx, 529, DeepSeek 503
  | 'badRequest' // 400/404/422: our request is wrong
  | 'network' // no answer, timeout
  | 'badResponse' // an answer we cannot read
  | 'noKey'; // the secret is not set

export class ProviderError extends Error {
  constructor(
    readonly kind: ProviderErrorKind,
    readonly status?: number,
  ) {
    // The message names the kind only; provider messages may echo request text.
    super(`provider error: ${kind}${status === undefined ? '' : ` (${status})`}`);
    this.name = 'ProviderError';
  }
}

/** The kind for an HTTP status (shared by the adapters). */
export function kindOfStatus(status: number): ProviderErrorKind {
  if (status === 401 || status === 403) return 'auth';
  if (status === 402) return 'billing';
  if (status === 429) return 'rateLimit';
  if (status >= 500) return 'overloaded';
  return 'badRequest';
}

/**
 * The provider-agnostic interface. Each adapter maps its API's content
 * blocks, usage and stop reasons to these shapes and its errors to
 * ProviderError.
 */
export interface AiProvider {
  readonly name: string;
  call(input: ProviderCall): Promise<ProviderResponse>;
}
