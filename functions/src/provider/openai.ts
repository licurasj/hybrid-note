import OpenAI from 'openai';

import { retryErrorText, retryInstruction, retryValidText } from '../prompt';
import {
  ProviderError,
  kindOfStatus,
  type AiProvider,
  type ContentBlock,
  type ProviderCall,
  type ProviderResponse,
} from './types';

const TIMEOUT_MS = 50_000;

/** 429 codes that mean no credit or a spend limit, not a rate limit (error-codes guide). */
const BILLING_CODES = new Set([
  'insufficient_quota',
  'credit_balance_exhausted',
  'organization_spend_limit_exceeded',
  'project_spend_limit_exceeded',
  'organization_usage_limit_exceeded',
]);

/**
 * OpenAI through the official SDK and the Responses API (W1, owner's wish
 * 2026-11-03). Read 2026-11-03 at developers.openai.com/api/docs: guides
 * function-calling, structured-outputs, reasoning, prompt-caching,
 * error-codes, your-data; models/gpt-6-luna; pricing. Function tools without
 * strict (strict mode needs every property required, which the schemas do
 * not meet; the function's schema check covers them); `tool_choice` auto;
 * `store: false`, so responses are not kept 30 days, with the reasoning sent
 * back encrypted on the retry; caching is automatic for the stable
 * tools + instructions prefix.
 */
export class OpenAiProvider implements AiProvider {
  readonly name = 'openai';
  private readonly client: OpenAI;

  constructor(apiKey: string | undefined, client?: OpenAI) {
    if (client === undefined && !apiKey) throw new ProviderError('noKey');
    this.client = client ?? new OpenAI({ apiKey, timeout: TIMEOUT_MS, maxRetries: 1 });
  }

  async call({ model, system, tools, user, retry }: ProviderCall): Promise<ProviderResponse> {
    const input: OpenAI.Responses.ResponseInputItem[] = [{ role: 'user', content: user }];
    if (retry !== undefined) {
      const previous = retry.previous.raw as OpenAI.Responses.ResponseOutputItem[] | undefined;
      if (!Array.isArray(previous)) throw new ProviderError('badResponse');
      // The previous output goes back as it came (reasoning items encrypted),
      // then one function_call_output per call.
      input.push(...(previous as OpenAI.Responses.ResponseInputItem[]));
      const failed = new Map(retry.feedback.map((f) => [f.id, f.errors]));
      for (const item of previous) {
        if (item.type !== 'function_call') continue;
        const errors = failed.get(item.call_id);
        input.push({
          type: 'function_call_output',
          call_id: item.call_id,
          output: errors === undefined ? retryValidText : retryErrorText(errors),
        });
      }
      input.push({ role: 'user', content: retryInstruction });
    }

    let response: OpenAI.Responses.Response;
    try {
      response = await this.client.responses.create({
        model: model.model,
        instructions: system,
        input,
        tools: tools.map((tool) => ({
          type: 'function',
          name: tool.name,
          description: tool.description,
          parameters: tool.input_schema,
          strict: false,
        })),
        tool_choice: 'auto',
        max_output_tokens: model.maxOutputTokens,
        ...(model.effort ? { reasoning: { effort: model.effort } } : {}),
        store: false,
        include: ['reasoning.encrypted_content'],
      });
    } catch (error) {
      throw mapError(error);
    }

    if (response.status === 'failed') throw new ProviderError('overloaded');
    const content: ContentBlock[] = [];
    let refused = false;
    for (const item of response.output) {
      if (item.type === 'function_call') {
        content.push({ type: 'tool_call', id: item.call_id, name: item.name, args: parseArgs(item.arguments) });
      } else if (item.type === 'message') {
        for (const part of item.content) {
          if (part.type === 'output_text' && part.text.trim().length > 0) content.push({ type: 'text', text: part.text });
          if (part.type === 'refusal') refused = true;
        }
      }
    }
    const usage = response.usage;
    const cached = usage?.input_tokens_details?.cached_tokens ?? 0;
    const written = usage?.input_tokens_details?.cache_write_tokens ?? 0;
    return {
      content,
      usage: {
        // input_tokens counts cached and cache-written tokens too.
        inputTokens: Math.max(0, (usage?.input_tokens ?? 0) - cached - written),
        outputTokens: usage?.output_tokens ?? 0,
        cacheReadTokens: cached,
        cacheWriteTokens: written,
      },
      stopReason: refused ? 'refusal' : stopReasonOf(response),
      raw: response.output,
    };
  }
}

export function stopReasonOf(response: Pick<OpenAI.Responses.Response, 'status' | 'incomplete_details'>): ProviderResponse['stopReason'] {
  if (response.status !== 'incomplete') return 'end';
  return response.incomplete_details?.reason === 'content_filter' ? 'refusal' : 'length';
}

/** Typed SDK errors to ProviderError kinds, most specific first (never by message text). */
export function mapError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (error instanceof OpenAI.APIConnectionError) return new ProviderError('network');
  if (error instanceof OpenAI.APIError && typeof error.status === 'number') {
    if (BILLING_CODES.has(error.code ?? '') || error.type === 'insufficient_quota') {
      return new ProviderError('billing', error.status);
    }
    return new ProviderError(kindOfStatus(error.status), error.status);
  }
  return new ProviderError('badResponse');
}

function parseArgs(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}
