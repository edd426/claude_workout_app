#!/bin/bash
# Rotate the shared Functions API key (the x-api-key the phone, the stdio MCP
# server and the claude.ai connector all send).
#
#   infra/scripts/rotate-api-key.sh          # rotate, verify
#   infra/scripts/rotate-api-key.sh --copy   # only copy the current key to the
#                                            # clipboard (Universal Clipboard
#                                            # reaches the phone)
#
# The key lives in five places; this script updates the first four:
#   1. macOS Keychain, service claudelifter-mcp, account functions-api-key
#   2. API_KEY app setting on func-workout-prod (the API itself)
#   3. FUNCTIONS_API_KEY app setting on func-workout-mcp-prod (claude.ai connector)
#   4. ~/.claude.json, the local stdio workout server's env, if configured
#      (since 2026-11-03 Claude Code uses the claude.ai connector instead)
#   5. the phone: Settings → Server API Key (by hand; paste from the clipboard)
#
# The API accepts one key at a time, so the phone cannot sync until step 5.
# No data is lost meanwhile: the phone is authoritative and pushes a full
# snapshot on its next sync. Claude Code must reconnect the workout MCP server
# (/mcp) to pick up the new env.
#
# No key is ever printed. App settings go through a mode-600 file, not the
# command line, so they stay out of the process list and Azure CLI's logs.

set -euo pipefail

RG="rg-workout-app-prod"
API_APP="func-workout-prod"
MCP_APP="func-workout-mcp-prod"
SERVICE="claudelifter-mcp"
ACCOUNT="functions-api-key"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="https://$API_APP.azurewebsites.net"

if [[ "${1:-}" == "--copy" ]]; then
  security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w | tr -d '\n' | pbcopy
  echo "current key copied to the clipboard"
  exit 0
fi

TMP=$(mktemp -d)
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

status_with() {  # status_with <file holding a key> → HTTP status of an authed read
  curl -s -o /dev/null -w '%{http_code}' -H @"$1" "$BASE/api/templates?limit=1"
}
header_file() {  # header_file <key> <path>: write an x-api-key header file (mode 600)
  ( umask 077; printf 'x-api-key: %s\n' "$1" > "$2" )
}

echo "== old key (for the before/after check)"
OLD=$(az functionapp config appsettings list -g "$RG" -n "$API_APP" \
  --query "[?name=='API_KEY'].value | [0]" -o tsv)
[[ -n "$OLD" ]] || { echo "could not read API_KEY from $API_APP" >&2; exit 1; }
header_file "$OLD" "$TMP/old.h"
unset OLD

echo "== new key → Keychain ($SERVICE / $ACCOUNT)"
NEW=$(uuidgen | tr '[:upper:]' '[:lower:]')
security add-generic-password -U -s "$SERVICE" -a "$ACCOUNT" -w "$NEW"
header_file "$NEW" "$TMP/new.h"

settings_file() {  # settings_file <name> <path>
  NAME="$1" VALUE="$NEW" python3 -I -c '
import json, os, sys
json.dump([{"name": os.environ["NAME"], "value": os.environ["VALUE"], "slotSetting": False}],
          open(sys.argv[1], "w"))' "$2"
  chmod 600 "$2"
}

echo "== $API_APP: API_KEY"
settings_file API_KEY "$TMP/api.json"
az functionapp config appsettings set -g "$RG" -n "$API_APP" --settings @"$TMP/api.json" -o none

echo "== $MCP_APP: FUNCTIONS_API_KEY"
settings_file FUNCTIONS_API_KEY "$TMP/mcp.json"
az functionapp config appsettings set -g "$RG" -n "$MCP_APP" --settings @"$TMP/mcp.json" -o none

echo "== ~/.claude.json: workout MCP env"
VALUE="$NEW" PROJECT="$REPO_DIR" python3 -I - <<'PY'
import json, os, tempfile
path = os.path.expanduser("~/.claude.json")
data = json.load(open(path))
server = data.get("projects", {}).get(os.environ["PROJECT"], {}).get("mcpServers", {}).get("workout")
if server is None:
    # Claude Code uses the claude.ai connector since 2026-11-03; nothing to update.
    print("no local workout server configured (skipped)")
    raise SystemExit(0)
server["env"]["FUNCTIONS_API_KEY"] = os.environ["VALUE"]
mode = os.stat(path).st_mode & 0o777
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp, mode)
os.replace(tmp, path)
print("updated")
PY
unset NEW

echo "== verify (the API restarts after a settings change)"
for _ in $(seq 1 18); do
  [[ "$(status_with "$TMP/new.h")" == "200" ]] && break
  sleep 10
done
NEW_STATUS=$(status_with "$TMP/new.h")
OLD_STATUS=$(status_with "$TMP/old.h")
echo "new key: $NEW_STATUS (want 200); old key: $OLD_STATUS (want 401)"
MCP=$(az functionapp config appsettings list -g "$RG" -n "$MCP_APP" \
  --query "[?name=='FUNCTIONS_API_KEY'].value | [0]" -o tsv | tr -d '\n' | shasum -a 256 | cut -c1-12)
CC=$(python3 -I -c '
import json, os, sys
d = json.load(open(os.path.expanduser("~/.claude.json")))
s = d.get("projects", {}).get(sys.argv[1], {}).get("mcpServers", {}).get("workout")
sys.stdout.write(s["env"]["FUNCTIONS_API_KEY"] if s else "")' "$REPO_DIR" \
  | shasum -a 256 | cut -c1-12)
KC=$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w | tr -d '\n' | shasum -a 256 | cut -c1-12)
[[ "$MCP" == "$KC" ]] && echo "connector app setting: matches Keychain" || echo "connector app setting: MISMATCH" >&2
EMPTY=$(printf '' | shasum -a 256 | cut -c1-12)
if [[ "$CC" == "$EMPTY" ]]; then CC="$KC"; echo "~/.claude.json: no local workout server (skipped)"
elif [[ "$CC" == "$KC" ]]; then echo "~/.claude.json: matches Keychain"
else echo "~/.claude.json: MISMATCH" >&2; fi
[[ "$NEW_STATUS" == "200" && "$OLD_STATUS" == "401" && "$MCP" == "$KC" && "$CC" == "$KC" ]] || exit 1
echo "done. Next: paste the key on the phone (run with --copy), then /mcp → reconnect workout in Claude Code."
