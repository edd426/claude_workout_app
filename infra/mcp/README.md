# ClaudeLifter Workout MCP Server

Read-only MCP server exposing ClaudeLifter workout data to Claude Code and
Claude Desktop (claude.ai), using Max-subscription tokens instead of API
billing.

## Architecture (v2 — issue #79)

The server is a **thin HTTP client of the Azure Functions API**. It
authenticates with the same `x-api-key` shared secret the iOS app uses — no
Azure CLI login, no `DefaultAzureCredential`, no Cosmos DB SDK.

```
Claude Code / Claude Desktop
        │ stdio
        ▼
  workout MCP server ──(HTTPS + x-api-key)──▶ Azure Functions API ──▶ Cosmos DB
```

v1 connected to Cosmos DB directly via `DefaultAzureCredential` and failed
with 403 on every query (no data-plane role assignment was provisioned).
v2 removes that entire auth path: one auth mechanism, one data-access layer.

## Read-only status

This server is **read-only**. The write tools (`create_template`,
`update_template`, `delete_template`, `create_program`) are hard-disabled and
return an explanatory error: the old direct-to-Cosmos write path produced
templates the iOS app could not resolve (invented `exerciseId`s, DTO drift).
Writes return once the write path is redesigned — tracked in issue #79.

`search_exercises` is also disabled: the app bundles the exercise library
locally and never syncs it, so the cloud `exercises` container is empty and
searches would silently return nothing.

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
npm run build   # emits dist/src/server.js
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

The Functions API endpoints backing these tools (all `GET`, all requiring
`x-api-key`, all bounded/validated):

| Endpoint | Query params |
|----------|--------------|
| `/api/templates` | `limit` (default 100, max 200) |
| `/api/templates/{id}` | — |
| `/api/workouts` | `startDate`, `endDate` (ISO 8601), `limit` (default 50, max 200) |
| `/api/workouts/{id}` | — |
| `/api/exercises/{exerciseId}/history` | `limit` (default 20, max 100) |
| `/api/stats` | `startDate`, `endDate` (scan capped at 500 most recent workouts) |
| `/api/calendar` | `startDate`, `endDate` (both required) |
| `/api/health` | — (anonymous) |

## Development

```bash
npm test         # vitest, HTTP client mocked — no network needed
npm run build    # tsc
```
