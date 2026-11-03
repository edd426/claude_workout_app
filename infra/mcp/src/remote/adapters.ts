/** Convert between Azure Functions HTTP objects and Fetch API Request/Response — issue #162. */

export interface AzureLikeRequest {
  method: string;
  url: string;
  headers: Headers;
  arrayBuffer(): Promise<ArrayBuffer>;
}

export interface AzureLikeResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export async function toWebRequest(req: AzureLikeRequest): Promise<Request> {
  const method = req.method.toUpperCase();
  const init: RequestInit = { method, headers: new Headers(req.headers) };
  if (method !== "GET" && method !== "HEAD") {
    init.body = await req.arrayBuffer();
  }
  return new Request(req.url, init);
}

export async function toHttpResponse(res: Response): Promise<AzureLikeResponse> {
  const headers: Record<string, string> = {};
  res.headers.forEach((value, key) => {
    headers[key] = value;
  });
  return { status: res.status, headers, body: await res.text() };
}
