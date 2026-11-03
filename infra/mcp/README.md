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
| `get_template` | Get a template with its exercises, each with its `alternatives` (#169) once the phone has mirrored v5 data; bundled alternatives are named from the catalog |
| `list_workouts` | List workout session summaries (optional `startDate`/`endDate`/`limit`) |
| `get_workout` | Full workout detail (exercises, sets, weights) |
| `get_exercise_history` | Past sets for one exercise across workouts |
| `get_stats` | Summary statistics: totals, PRs, workouts/week |
| `get_calendar` | Per-day workout frequency for a date range |
| `search_exercises` | Ranked bundled-catalog search merged with synced custom exercises |
| `create_template` | Validate exercise IDs (alternatives included) and enqueue a template |
| `update_template` | Enqueue a template update for approval. Per exercise, `alternatives` omitted keeps the slot's list, `[]` clears it, a list replaces it (#169) |
| `delete_template` | Enqueue a template deletion for approval |
| `create_program` | Validate all templates, then enqueue each |
| `create_custom_exercise` | Enqueue a custom exercise |
| `attach_exercise_photo` | Attach a JPEG (≤ 3.75 MB) to an exercise: uploads it, then enqueues `setExercisePhoto` for approval on the phone (#170). Takes `externalId` plus exactly one of `imagePath` (absolute path to a local `.jpg`/`.jpeg`; **local stdio server only**, symlinks resolved) or `imageBase64` (both servers) |
| `list_body_measurements` | Circumference log (`site`, `startDate`, `endDate`, `limit`), the stored height, and the current waist-to-height ratio with its NICE NG246 band (#165) |
| `list_medications` | The medication log's medications (`includeArchived`), with each one's current concentration (#164) |
| `list_medication_logs` | Logged doses (`medicationId`, `startDate`, `endDate`, `limit`) with medication names; `computedMg` and the `…AtLog` values exactly as logged (#164) |
| `list_exercise_reports` | Read the complaint backlog filed from the app (defaults to unresolved); a non-null `photoURL` means a photo is attached |
| `get_report_photo` | View the photo attached to a report (`id`): a caption naming the report plus the JPEG as image content. No `photoURL` means no photo, or one the phone has not uploaded yet |
| `resolve_exercise_report` | Enqueue a close-out for one report (`resolved` / `acknowledged`) |
| `list_pending_writes` | List inbox operations by status |
| `delete_inbox_operation` | Permanently delete one or more terminal (applied/rejected/failed) inbox operations |
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

Since 2026-11-03 Claude Code uses the **claude.ai connector** (below): once it is
added on claude.ai, its tools appear in Claude Code as `mcp__claude_ai_ClaudeLifter__*`,
so Claude Code tests the same server everyone else uses. The local stdio config
here is for trying unreleased tool changes before a deploy.

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

## Remote server: the claude.ai connector (#162)

The same tools are served over Streamable HTTP for claude.ai (web, desktop,
mobile) from a Function App of their own:

**Connector URL: `https://func-workout-mcp-prod.azurewebsites.net/mcp`**
(claude.ai → Settings → Connectors → Add custom connector; no client ID or
secret needed: the server registers claude.ai itself).

```
claude.ai ──HTTPS + Entra bearer token──▶ func-workout-mcp-prod (/mcp, OAuth proxy)
                                                 │ HTTPS + x-api-key (server-side)
                                                 ▼
                                          func-workout-prod (the phone's API, unchanged)
```

- **Code**: `src/azure/functions.ts` (routes) over `src/remote/` (pure,
  unit-tested: `auth.ts` token checks, `oauth.ts` proxy rules, `mcpHandler.ts`
  the `/mcp` endpoint) and `src/serverFactory.ts`, which the stdio server uses
  too, so both expose identical tools. Stateless: a fresh server per request,
  JSON responses, no SSE.
- **Infra**: `infra/modules/mcpFunctions.bicep`, deployed on its own: Flex
  Consumption (Azure refuses new Linux Consumption apps in this resource
  group), a dedicated storage account, logs to the existing `ai-workout-prod`.
- **Entra app** "ClaudeLifter Workout MCP" (`infra/scripts/setup-mcp-entra-app.sh`,
  run once): scope `api://<clientId>/workout.access`, v2 tokens.

### Security model

| Control | Where |
|---|---|
| Only Evan can sign in: single tenant, *assignment required*, one user assigned | Entra app |
| Redirects only to Claude's two callbacks | Entra app (the real control) and the proxy (exact match) |
| PKCE S256 required; the token proxy forwards only `authorization_code` and `refresh_token` | `oauth.ts` |
| Bearer token verified against Entra's keys: RS256, issuer, audience, `tid`, `scp=workout.access` (rejects ID tokens) | `auth.ts` |
| `ALLOWED_OIDS` allowlist; **unset admits nobody** | `auth.ts`, app setting |
| 401 answers carry no reason; tokens and codes are never logged | `mcpHandler.ts`, `functions.ts` |
| HTTPS only, TLS 1.2+, FTP disabled; the client secret and API key exist only as app settings and in the Keychain | Bicep |
| Writes are still inbox operations you approve on the phone | unchanged |

Known gap: the app holds the full-power `API_KEY`. A key scoped to the read and
inbox routes would shrink the damage if it ever leaked (follow-up in #162).

### Deploy

```bash
cd infra/mcp
npm run deploy:remote            # build, test, Bicep, publish, smoke test
npm run deploy:remote -- --code  # code only
```

`scripts/deploy-remote.sh` reads the API key from `func-workout-prod`'s settings
and the Entra client id and secret from the Keychain (service
`claudelifter-mcp`, accounts `entra-client-id` / `entra-client-secret`); it
prints none of them. The secret expires **2027-11-02**: rotate with the command
at the top of `setup-mcp-entra-app.sh`, then run a full deploy.

To rotate the shared API key, run `infra/scripts/rotate-api-key.sh`. It updates
the Keychain (`claudelifter-mcp` / `functions-api-key`), both Function Apps and
`~/.claude.json`, and checks that the new key gets 200 and the old one 401. Then
`--copy` puts the key on the clipboard for the phone's Settings → Server API Key.
Last rotated 2026-11-03.

The local Functions host (`func start`) needs Node 22; the dev Mac runs Node 26,
which it refuses, so check routes against the deployed app instead.

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
| `/api/body-measurements` | `site`, `startDate`, `endDate`, `limit` (default 100, max 500); returns `{ mirrored, heightCm, measurements, latestWaist }` |
| `/api/medications` | `includeArchived` (`true`/`false`, default false); returns `{ mirrored, medications }` sorted by name |
| `/api/medication-doses` | `medicationId` (404 if unknown), `startDate`, `endDate`, `limit` (default 100, max 500); returns `{ mirrored, doses }` newest first, each with `medicationName` |
| `/api/images/sas` | `path` (`reports/{reportId}.jpg` for report photos, `exercises/ext/{externalId}.jpg` for exercise photos), `mode` (`download`/`upload`); returns `{ sasUrl, expiresAt }` |
| `/api/inbox` | `GET ?status=` lists operations; `POST` enqueues one |
| `/api/health` | — (anonymous) |

The three v5 reads answer `mirrored: false` (and read nothing) until the phone
has pushed snapshot wire v5 at least once, so "not synced yet" is never
reported as "none". Their date bounds are UTC; a date alone as `endDate`
includes that whole day. Medication and measurement data is health data: the
Functions log errors only, never documents.

### Exercise photos (`attach_exercise_photo`, #170)

1. The externalId must match the photo-path grammar exactly: a catalog id
   (`[A-Za-z0-9][A-Za-z0-9_-]{0,127}`) or a custom id
   (`custom:{slug}:{lowercase uuid}`). No `/`, `.`, `%` or whitespace, so it
   cannot leave `exercises/ext/`. The image, from `imagePath` or
   `imageBase64`, must be a JPEG of at most 3.75 MB. Both are checked before
   any request.
2. The exercise must exist: the bundled catalog, or a synced or queued
   custom exercise.
3. A **write** SAS for `exercises/ext/{externalId}.jpg` comes from
   `/api/images/sas`; the tool refuses one for any other blob, uploads
   **directly to Blob Storage** with that SAS only (never the API key), and
   never prints the SAS URL.
4. Only after the upload, it enqueues `setExercisePhoto { externalId, blobPath }`.
   The Function marks it `requiresApproval`; the phone applies it on approval
   and downloads the photo with a read SAS for the same path.

A 400 from `/api/images/sas` or from the enqueue usually means the deployed
Functions app predates #170. The claude.ai transport accepts request bodies up
to 6 MiB (the SDK default is 4 MiB) so a photo at the limit fits.

**Two ways to send the image** (exactly one per call):

- `imagePath`, the bulk path: an absolute path to a local `.jpg`/`.jpeg`.
  The server reads it with filesystem calls only (no shell). It resolves
  symlinks and applies every check to the real file: it must be a regular
  file with a `.jpg`/`.jpeg` name, at most 3.75 MB, starting with the JPEG
  magic bytes. **Only the local stdio server accepts it** (`createLocalServer`
  in `src/serverFactory.ts`). The claude.ai server runs on Azure, where a path
  would name a file on the Function host. It does not list `imagePath` and
  refuses it with "imagePath is only available on the local server; send
  imageBase64". For a gym's worth of photos, run the stdio server locally (see
  Claude Code above) and pass paths.
- `imageBase64`, on both servers: the model has to write out the whole base64
  text (a typical 200 KB photo is ~270,000 characters of output), so it suits
  a few photos at most. claude.ai has no way to hand an uploaded image's bytes
  to a tool.

### Report photos (`get_report_photo`, #141)

The phone uploads a report's photo to blob `reports/{reportId}.jpg` in the
`workout-images` container, and only after that upload succeeds sets the
report's `photoURL` to that path, not a URL. The tool then:

1. finds the report through `/api/reports?status=all` (the id match ignores
   case, because the mirror holds Swift's upper-case UUIDs);
2. checks that `photoURL` is exactly `reports/{thisReportId}.jpg`, and refuses
   anything else before any SAS request;
3. gets a read SAS from `/api/images/sas`, then downloads the blob **directly
   from Blob Storage**. This is the only request that does not go to the
   Functions API, and it never carries the API key;
4. refuses a blob larger than 3.75 MB (so the base64 stays within the 5 MB
   per-image limit; real photos are ~100–300 KB) and a blob that is not a
   JPEG.

A 404 from storage means the report points at a photo that is not there. A
400 from `/api/images/sas` usually means the deployed Functions app predates
#141, which added the `reports/` path family, and needs redeploying.

## Development

```bash
npm test         # vitest, HTTP client mocked — no network needed
npm run build    # tsc
```
