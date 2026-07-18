// Minimal stub for @azure/functions used in tests
export const app = {
  http: jest.fn(),
};

export class HttpRequest {
  private _body: unknown;
  private _headers: Record<string, string>;
  private _query: URLSearchParams;
  private _params: Record<string, string>;

  // The real HttpRequest has a complex constructor; our test version just takes
  // a body, an optional headers map, and optional { query, params } for
  // GET endpoints with query strings / route parameters.
  constructor(...args: unknown[]) {
    this._body = args[0];
    this._headers = (args[1] as Record<string, string>) ?? {};
    const options =
      (args[2] as {
        query?: Record<string, string>;
        params?: Record<string, string>;
      }) ?? {};
    this._query = new URLSearchParams(options.query ?? {});
    this._params = options.params ?? {};
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

  get query(): URLSearchParams {
    return this._query;
  }

  get params(): Record<string, string> {
    return this._params;
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
