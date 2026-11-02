#!/bin/bash
# Build, test, and deploy the remote MCP (claude.ai connector) — issue #162.
#
#   cd infra/mcp && npm run deploy:remote            # infra + code
#   cd infra/mcp && npm run deploy:remote -- --code  # code only
#
# Secrets are read from Azure (the API key, from func-workout-prod's settings)
# and the macOS Keychain (the Entra client secret, written by
# infra/scripts/setup-mcp-entra-app.sh). None is printed.

set -euo pipefail

RG="rg-workout-app-prod"
APP="func-workout-mcp-prod"
API_APP="func-workout-prod"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CODE_ONLY=false
[[ "${1:-}" == "--code" ]] && CODE_ONLY=true

cd "$HERE"
echo "== build and test"
npm ci
npm run clean
npm run build
npm test

if ! $CODE_ONLY; then
  echo "== infrastructure ($APP)"
  CLIENT_ID=$(security find-generic-password -s claudelifter-mcp -a entra-client-id -w)
  CLIENT_SECRET=$(security find-generic-password -s claudelifter-mcp -a entra-client-secret -w)
  API_KEY=$(az functionapp config appsettings list -g "$RG" -n "$API_APP" --query "[?name=='API_KEY'].value | [0]" -o tsv)
  TENANT_ID=$(az account show --query tenantId -o tsv)
  USER_OID=$(az ad signed-in-user show --query id -o tsv)
  [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" && -n "$API_KEY" && -n "$USER_OID" ]] || { echo "missing a secret or id" >&2; exit 1; }
  # Secrets go in a temporary parameters file (mode 600), not on the command line.
  PARAMS=$(mktemp)
  chmod 600 "$PARAMS"
  trap 'rm -f "$PARAMS"' EXIT
  python3 -I - "$PARAMS" "$API_KEY" "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" "$USER_OID" <<'PY'
import json, sys
path, api_key, tenant, client, secret, oid = sys.argv[1:]
p = {"functionsApiKey": api_key, "entraTenantId": tenant, "entraClientId": client,
     "entraClientSecret": secret, "allowedOids": oid}
json.dump({"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
           "contentVersion": "1.0.0.0", "parameters": {k: {"value": v} for k, v in p.items()}}, open(path, "w"))
PY
  unset API_KEY CLIENT_SECRET
  az deployment group create -g "$RG" \
    --name "mcp-remote-$(date +%Y%m%d%H%M%S)" \
    --template-file "$REPO/infra/modules/mcpFunctions.bicep" \
    --parameters "@$PARAMS" \
    --query "properties.outputs" -o json
  rm -f "$PARAMS"
fi

echo "== code ($APP)"
# Ship the locally built dist/ with production dependencies only. A remote
# build cannot work: the catalog build reads ClaudeLifter/Resources/exercises.json.
npm prune --omit=dev
func azure functionapp publish "$APP" --javascript --build local
npm install   # restore dev dependencies

echo "== smoke"
BASE="https://$APP.azurewebsites.net"
for i in 1 2 3 4 5 6; do
  curl -sf "$BASE/health" >/dev/null && break
  sleep 10
done
curl -sf "$BASE/health"; echo
curl -sf "$BASE/.well-known/oauth-protected-resource/mcp" >/dev/null && echo "resource metadata: ok"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/mcp" -H 'content-type: application/json' -d '{}')
[[ "$STATUS" == "401" ]] && echo "/mcp without a token: 401 (ok)" || { echo "/mcp without a token answered $STATUS" >&2; exit 1; }
