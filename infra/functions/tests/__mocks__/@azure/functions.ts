// Minimal stub for @azure/functions used in tests
export const app = {
  http: jest.fn(),
};

export class HttpRequest {
  private _body: unknown;
  private _headers: Record<string, string>;

  // The real HttpRequest has a complex constructor; our test version just takes
  // a body and an optional headers map for convenience.
  constructor(...args: unknown[]) {
    this._body = args[0];
    this._headers = (args[1] as Record<string, string>) ?? {};
  }

  async json() {
    return this._body;
  }

  get headers() {
    const hdrs = this._headers;
    return {
      get: (name: string) => hdrs[name.toLowerCase()] ?? null,
    };
  }
}

export class InvocationContext {
  log = jest.fn();
  error = jest.fn();
  warn = jest.fn();
}

export interface HttpResponseInit {
  status?: number;
  jsonBody?: unknown;
  body?: unknown;
  headers?: Record<string, string>;
}
