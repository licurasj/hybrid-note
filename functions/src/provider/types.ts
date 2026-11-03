import type { ModelConfig } from '../config';
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

export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'tool_call'; name: string; args: unknown };

export interface ProviderResponse {
  content: ContentBlock[];
  usage: { inputTokens: number; outputTokens: number };
  /** `refusal`: the provider's own safety stop; `length`: cut at the output ceiling. */
  stopReason: 'end' | 'refusal' | 'length';
}

export interface ProviderCall {
  model: ModelConfig;
  system: string;
  request: AiRequest;
}

/**
 * The provider-agnostic interface. T-19 unit 3 adds the Claude and DeepSeek
 * adapters; each maps its API's content blocks, usage and stop reasons to
 * these shapes and its errors to `refuse('provider')`.
 */
export interface AiProvider {
  readonly name: string;
  call(input: ProviderCall): Promise<ProviderResponse>;
}
