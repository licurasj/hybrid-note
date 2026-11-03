import { retryErrorText, retryInstruction, retryValidText } from '../prompt';
import {
  ProviderError,
  kindOfStatus,
  type AiProvider,
  type ContentBlock,
  type ProviderCall,
  type ProviderResponse,
} from './types';

// DeepSeek's documented chat completions API (OpenAI format), read 2026-11-03:
// api-docs.deepseek.com/api/create-chat-completion, /guides/tool_calls,
// /guides/kv_cache, /quick_start/error_codes. DeepSeek has no official Node
// SDK, so this is plain fetch. Strict mode needs the /beta base URL and every
// property required, which the tool schemas do not meet, so it is not used.
export const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const TIMEOUT_MS = 50_000;

interface DeepSeekToolCall {
  id: string;
  type: 'function';
  function: { name: string; arguments: string };
}

interface DeepSeekMessage {
  role: 'assistant';
  content: string | null;
  reasoning_content?: string | null;
  tool_calls?: DeepSeekToolCall[];
}

interface DeepSeekCompletion {
  choices: { message: DeepSeekMessage; finish_reason: string }[];
  usage: {
    prompt_cache_hit_tokens?: number;
    prompt_cache_miss_tokens?: number;
    prompt_tokens: number;
    completion_tokens: number;
  };
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

/**
 * DeepSeek V4.1 Flash (`deepseek-flash`, Q-28). The prompt order is the same
 * as Claude's (tools, system, then the request), which suits DeepSeek's
 * automatic prefix cache. Thinking is DeepSeek's default and stays on with
 * `reasoning_effort` from config; `tool_choice` auto.
 */
export class DeepSeekProvider implements AiProvider {
  readonly name = 'deepseek';

  constructor(
    private readonly apiKey: string | undefined,
    private readonly fetchFn: Fetch = fetch,
  ) {
    if (!apiKey) throw new ProviderError('noKey');
  }

  async call({ model, system, tools, user, retry }: ProviderCall): Promise<ProviderResponse> {
    const messages: unknown[] = [
      { role: 'system', content: system },
      { role: 'user', content: user },
    ];
    if (retry !== undefined) {
      const previous = retry.previous.raw as DeepSeekMessage | undefined;
      if (previous === undefined || previous.role !== 'assistant') throw new ProviderError('badResponse');
      // The reasoning goes back with the tool calls of the same turn.
      messages.push(previous);
      const failed = new Map(retry.feedback.map((f) => [f.id, f.errors]));
      for (const call of previous.tool_calls ?? []) {
        const errors = failed.get(call.id);
        messages.push({
          role: 'tool',
          tool_call_id: call.id,
          content: errors === undefined ? retryValidText : retryErrorText(errors),
        });
      }
      messages.push({ role: 'user', content: retryInstruction });
    }

    const body = {
      model: model.model,
      messages,
      tools: tools.map((tool) => ({
        type: 'function',
        function: { name: tool.name, description: tool.description, parameters: tool.input_schema },
      })),
      tool_choice: 'auto',
      max_tokens: model.maxOutputTokens,
      ...(model.effort ? { reasoning_effort: model.effort === 'medium' ? 'high' : model.effort } : {}),
      stream: false,
    };

    const completion = await this.post(body);
    const choice = completion.choices?.[0];
    if (choice === undefined || choice.message === undefined) throw new ProviderError('badResponse');
    if (choice.finish_reason === 'insufficient_system_resource' || choice.finish_reason === 'aborted') {
      throw new ProviderError('overloaded');
    }

    const content: ContentBlock[] = [];
    if (typeof choice.message.content === 'string' && choice.message.content.trim().length > 0) {
      content.push({ type: 'text', text: choice.message.content });
    }
    for (const call of choice.message.tool_calls ?? []) {
      content.push({ type: 'tool_call', id: call.id, name: call.function.name, args: parseArgs(call.function.arguments) });
    }
    const usage = completion.usage;
    const hit = usage.prompt_cache_hit_tokens ?? 0;
    return {
      content,
      usage: {
        inputTokens: usage.prompt_cache_miss_tokens ?? usage.prompt_tokens - hit,
        outputTokens: usage.completion_tokens,
        cacheReadTokens: hit,
        cacheWriteTokens: 0,
      },
      stopReason: stopReasonOf(choice.finish_reason),
      raw: choice.message,
    };
  }

  /** One POST, retried once after a second on 429, 5xx or no answer (like the Claude SDK). */
  private async post(body: unknown): Promise<DeepSeekCompletion> {
    let last: ProviderError = new ProviderError('network');
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await new Promise((resolve) => setTimeout(resolve, 1000));
      let response: Response;
      try {
        response = await this.fetchFn(DEEPSEEK_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${this.apiKey}` },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch {
        last = new ProviderError('network');
        continue;
      }
      if (response.ok) {
        try {
          return (await response.json()) as DeepSeekCompletion;
        } catch {
          throw new ProviderError('badResponse', response.status);
        }
      }
      last = new ProviderError(kindOfStatus(response.status), response.status);
      if (last.kind !== 'rateLimit' && last.kind !== 'overloaded') throw last;
    }
    throw last;
  }
}

function parseArgs(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

export function stopReasonOf(reason: string): ProviderResponse['stopReason'] {
  if (reason === 'length') return 'length';
  if (reason === 'content_filter') return 'refusal';
  return 'end';
}
