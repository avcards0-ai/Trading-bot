import { z } from 'zod';
import { ProviderError } from './errors';
import type { HttpClient } from './http';

const rpcResponse = z.object({
  jsonrpc: z.literal('2.0').optional(),
  id: z.union([z.number(), z.string(), z.null()]).optional(),
  result: z.unknown().optional(),
  error: z
    .object({ code: z.number(), message: z.string(), data: z.unknown().optional() })
    .optional(),
});

/** JSON-RPC 2.0 over the shared HttpClient (inherits retries, rate limits and circuit breaking). */
export class JsonRpcClient {
  private id = 0;

  constructor(private readonly http: HttpClient) {}

  get name(): string {
    return this.http.name;
  }

  health() {
    return this.http.health();
  }

  async call<T>(method: string, params: unknown[] = [], schema?: z.ZodType<T>): Promise<T> {
    this.id += 1;
    const res = await this.http.post('', { jsonrpc: '2.0', id: this.id, method, params }, { schema: rpcResponse });
    if (res.error) {
      // -32005 / -32429 are node-provider rate limit codes; treat as retryable upstream conditions.
      const retryable = res.error.code === -32005 || res.error.code === -32429;
      throw new ProviderError(this.http.name, `RPC ${method} error ${res.error.code}: ${res.error.message}`, null, retryable);
    }
    if (schema) {
      const parsed = schema.safeParse(res.result);
      if (!parsed.success) {
        const issue = parsed.error.issues[0];
        throw new ProviderError(
          this.http.name,
          `RPC ${method} returned unexpected shape at ${issue?.path.join('.') || '(root)'}: ${issue?.message}`,
        );
      }
      return parsed.data;
    }
    return res.result as T;
  }
}
