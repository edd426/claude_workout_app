import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { HealthResponse } from "../shared/types";

app.http("health", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "health",
  handler: async (
    _request: HttpRequest,
    _context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const response: HealthResponse = {
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: "2.0.0",
    };
    return { jsonBody: response };
  },
});
