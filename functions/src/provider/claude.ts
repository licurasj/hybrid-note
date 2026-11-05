import Anthropic from '@anthropic-ai/sdk';

import { retryErrorText, retryInstruction, retryValidText } from '../prompt';

import {
  ProviderError,
  kindOfStatus,
  type AiProvider,
  type ContentBlock,
  type ProviderCall,
  type ProviderResponse,
} from './types';

/** The default time of one Messages call; retries are runModel's (one place, one deadline). */
const TIMEOUT_MS = 50_000;

/**
 * Claude through the official SDK (Q-28: Haiku 5.5, Sonnet 5.5 as fallback).
 * Request shape per the claude-api skill (cached 2026-10-06): tools then the
 * system prompt with one cache breakpoint at its end, so both stay one cached
 * prefix; `tool_choice` auto (forced tool use is refused by some current
 * models); adaptive thinking left at the model default with `effort` from
 * config; no sampling parameters (Haiku 5.5 refuses non-default ones).
 */
export class ClaudeProvider implements AiProvider {
  readonly name = 'claude';
  private readonly client: Anthropic;

  constructor(apiKey: string | undefined, client?: Anthropic) {
    if (client === undefined && !apiKey) throw new ProviderError('noKey');
    this.client = client ?? new Anthropic({ apiKey, timeout: TIMEOUT_MS, maxRetries: 0 });
  }

  async call({ model, system, tools, user, retry, timeoutMs }: ProviderCall): Promise<ProviderResponse> {
    const messages: Anthropic.MessageParam[] = [{ role: 'user', content: user }];
    if (retry !== undefined) {
      const previous = retry.previous.raw as Anthropic.ContentBlock[] | undefined;
      if (!Array.isArray(previous)) throw new ProviderError('badResponse');
      // Thinking blocks go back unchanged; every tool_use gets a tool_result.
      messages.push({ role: 'assistant', content: previous as Anthropic.ContentBlockParam[] });
      const failed = new Map(retry.feedback.map((f) => [f.id, f.errors]));
      const results: Anthropic.ToolResultBlockParam[] = previous
        .filter((block): block is Anthropic.ToolUseBlock => block.type === 'tool_use')
        .map((block) => {
          const errors = failed.get(block.id);
          return errors === undefined
            ? { type: 'tool_result', tool_use_id: block.id, content: retryValidText }
            : { type: 'tool_result', tool_use_id: block.id, is_error: true, content: retryErrorText(errors) };
        });
      messages.push({ role: 'user', content: [...results, { type: 'text', text: retryInstruction }] });
    }

    let response: Anthropic.Message;
    try {
      response = await this.client.messages.create({
        model: model.model,
        max_tokens: model.maxOutputTokens,
        system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
        tools: tools.map((tool) => ({
          name: tool.name,
          description: tool.description,
          input_schema: tool.input_schema as Anthropic.Tool.InputSchema,
          ...(tool.strict ? { strict: true } : {}),
        })),
        tool_choice: { type: 'auto' },
        ...(model.effort ? { output_config: { effort: model.effort } } : {}),
        messages,
      }, { timeout: timeoutMs ?? TIMEOUT_MS });
    } catch (error) {
      throw mapError(error);
    }

    const content: ContentBlock[] = [];
    for (const block of response.content) {
      if (block.type === 'text') content.push({ type: 'text', text: block.text });
      if (block.type === 'tool_use') content.push({ type: 'tool_call', id: block.id, name: block.name, args: block.input });
    }
    const usage = response.usage;
    return {
      content,
      usage: {
        inputTokens: usage.input_tokens,
        outputTokens: usage.output_tokens,
        cacheReadTokens: usage.cache_read_input_tokens ?? 0,
        cacheWriteTokens: usage.cache_creation_input_tokens ?? 0,
      },
      stopReason: stopReasonOf(response.stop_reason),
      raw: response.content,
    };
  }
}

export function stopReasonOf(reason: Anthropic.StopReason | null): ProviderResponse['stopReason'] {
  switch (reason) {
    case 'refusal':
      return 'refusal';
    case 'max_tokens':
    case 'model_context_window_exceeded':
      return 'length';
    default:
      return 'end';
  }
}

/** Typed SDK errors to ProviderError kinds, most specific first (never by message text). */
export function mapError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (error instanceof Anthropic.APIConnectionError) return new ProviderError('network');
  if (error instanceof Anthropic.APIError && typeof error.status === 'number') {
    if (error.type === 'billing_error') return new ProviderError('billing', error.status);
    return new ProviderError(kindOfStatus(error.status), error.status);
  }
  return new ProviderError('badResponse');
}
