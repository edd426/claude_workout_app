# ClaudeLifter Workout MCP Server

MCP server exposing ClaudeLifter workout data and durable inbox writes to
Claude Code and Claude Desktop.

## Architecture

The server is a **thin HTTP client of the Azure Functions API**. It
authenticates with the same `x-api-key` shared secret the iOS app uses — no
Azure CLI login, no `DefaultAzureCredential`, no Cosmos DB SDK.

```
Claude Code / Claude Desktop
        │ stdio
        ▼
  workout MCP server ──(HTTPS + x-api-key)──▶ Azure Functions API ──▶ Cosmos DB
          │                                                │
          └── bundled exercise catalog                     └── inbox → iPhone
```

v1 connected to Cosmos DB directly via `DefaultAzureCredential` and failed
with 403 on every query (no data-plane role assignment was provisioned).
v2 removes that entire auth path: one auth mechanism, one data-access layer.

Read tools query the phone-authoritative cloud mirror. Write tools enqueue
operations in `/api/inbox`; the iPhone drains and applies that inbox during
sync. Every template exercise uses a stable `externalId`, validated against a
slim build-time catalog before any write request is sent.

## Tools

| Tool | Description |
|------|-------------|
| `list_templates` | List all workout templates |
| `get_template` | Get a template with its exercises |
| `list_workouts` | List workout session summaries (optional `startDate`/`endDate`/`limit`) |
| `get_workout` | Full workout detail (exercises, sets, weights) |
| `get_exercise_history` | Past sets for one exercise across workouts |
| `get_stats` | Summary statistics: totals, PRs, workouts/week |
| `get_calendar` | Per-day workout frequency for a date range |
| `search_exercises` | Ranked bundled-catalog search merged with synced custom exercises |
| `create_template` | Validate exercise IDs and enqueue a template |
| `update_template` | Enqueue a template update for approval |
| `delete_template` | Enqueue a template deletion for approval |
| `create_program` | Validate all templates, then enqueue each |
| `create_custom_exercise` | Enqueue a custom exercise |
| `list_exercise_reports` | Read the complaint backlog filed from the app (defaults to unresolved) |
| `resolve_exercise_report` | Enqueue a close-out for one report (`resolved` / `acknowledged`) |
| `list_pending_writes` | List inbox operations by status |
| `health` | Diagnostic: Functions API connectivity + auth status + base URL |

If something isn't working, call the `health` tool first — it reports whether
the Functions API is reachable and whether the API key is accepted, without
ever printing the key.

## Configuration

Two environment variables (both required):

| Variable | Value |
|----------|-------|
| `FUNCTIONS_BASE_URL` | Function App base URL, e.g. `https://func-workout-prod.azurewebsites.net` (no `/api` suffix) |
| `FUNCTIONS_API_KEY` | The shared secret matching the `API_KEY` app setting on the Function App |

Never commit the API key; keep it in your local MCP config only.

### Build

```bash
cd infra/mcp
npm install
npm run build   # emits dist/src/server.js and dist/catalog-index.json
```

### Claude Code

`.mcp.json` (project) or `~/.claude.json` (user):

```json
{
  "mcpServers": {
    "workout": {
      "command": "node",
      "args": ["/path/to/claude_workout_app/infra/mcp/dist/src/server.js"],
      "env": {
        "FUNCTIONS_BASE_URL": "https://func-workout-prod.azurewebsites.net",
        "FUNCTIONS_API_KEY": "<shared-api-key>"
      }
    }
  }
}
```

Or via CLI:

```bash
claude mcp add workout \
  -e FUNCTIONS_BASE_URL=https://func-workout-prod.azurewebsites.net \
  -e FUNCTIONS_API_KEY=<shared-api-key> \
  -- node /path/to/claude_workout_app/infra/mcp/dist/src/server.js
```

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "workout": {
      "command": "node",
      "args": ["/path/to/claude_workout_app/infra/mcp/dist/src/server.js"],
      "env": {
        "FUNCTIONS_BASE_URL": "https://func-workout-prod.azurewebsites.net",
        "FUNCTIONS_API_KEY": "<shared-api-key>"
      }
    }
  }
}
```

## Backing API endpoints

The Functions API endpoints backing these tools all require `x-api-key`
except health:

| Endpoint | Query params |
|----------|--------------|
| `/api/templates` | `limit` (default 100, max 200) |
| `/api/templates/{id}` | — |
| `/api/workouts` | `startDate`, `endDate` (ISO 8601), `limit` (default 50, max 200) |
| `/api/workouts/{id}` | — |
| `/api/exercises/{exerciseId}/history` | `limit` (default 20, max 100) |
| `/api/stats` | `startDate`, `endDate` (scan capped at 500 most recent workouts) |
| `/api/calendar` | `startDate`, `endDate` (both required) |
| `/api/sync/snapshot` | supplies `snapshot.customExercises` for catalog search |
| `/api/reports` | `status` (open/acknowledged/resolved/all), `category`, `exerciseExternalId`, `limit` (default 100, max 500) |
| `/api/inbox` | `GET ?status=` lists operations; `POST` enqueues one |
| `/api/health` | — (anonymous) |

## Development

```bash
npm test         # vitest, HTTP client mocked — no network needed
npm run build    # tsc
```
