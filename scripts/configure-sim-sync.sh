#!/usr/bin/env bash
# Programmatically configure ClaudeLifter on a booted iOS simulator to talk to
# Azure: writes Server URL + API Key into the app's UserDefaults so the user
# doesn't have to type a 36-char key on a phone keyboard.
#
# Why this is needed: SyncManager silently no-ops when settings.serverURL is
# empty (Services/Sync/SyncManager.swift). Until both Server URL and API Key
# are set, the app runs in standalone Phase 1 mode and never reaches Cosmos.
#
# Notes on the API key:
#   - In production the app keychain-backs the key at "anthropic_api_key".
#   - On first read, SettingsManager migrates from UserDefaults → Keychain, so
#     writing to UserDefaults here is correct: the app moves it on next launch.
#   - The Function App's API_KEY is what the iOS app sends as auth; the
#     Function uses its own ANTHROPIC_API_KEY server-side to call the upstream.
#
# Requirements: a booted iOS simulator with ClaudeLifter installed at least
# once (so its data container exists), and `az` logged in.

set -euo pipefail

BUNDLE_ID="com.eddelord.ClaudeLifter"
SERVER_URL="${SERVER_URL:-https://func-workout-prod.azurewebsites.net}"
RG="${RG:-rg-workout-app-prod}"
FUNC="${FUNC:-func-workout-prod}"

err() { printf '%s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m›\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; }

command -v xcrun >/dev/null || err "xcrun not found — install Xcode command-line tools"
command -v az    >/dev/null || err "az not found — install the Azure CLI"
command -v plutil >/dev/null || err "plutil not found"

# 1. Find the booted simulator.
DEVICE_UDID=$(xcrun simctl list devices booted -j \
  | python3 -c "import sys,json; ds=[d for v in json.load(sys.stdin)['devices'].values() for d in v if d.get('state')=='Booted']; print(ds[0]['udid'] if ds else '')")
[ -n "$DEVICE_UDID" ] || err "no booted simulator — open Xcode > Window > Devices and Simulators, or run 'xcrun simctl boot <id>'"
DEVICE_NAME=$(xcrun simctl list devices booted -j \
  | python3 -c "import sys,json; ds=[d for v in json.load(sys.stdin)['devices'].values() for d in v if d.get('state')=='Booted']; print(ds[0]['name'] if ds else '')")
log "booted simulator: $DEVICE_NAME ($DEVICE_UDID)"

# 2. Find the app's data container. This only exists if the app has been
#    installed and launched at least once.
APP_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_UDID" "$BUNDLE_ID" data 2>/dev/null) \
  || err "$BUNDLE_ID is not installed on the simulator. Build & run it once from Xcode, then re-run this script."
PREFS_PLIST="$APP_CONTAINER/Library/Preferences/$BUNDLE_ID.plist"
log "app data container: $APP_CONTAINER"

# 3. Pull the Function App's API_KEY from Azure.
log "fetching API_KEY from $FUNC ..."
API_KEY=$(az functionapp config appsettings list -g "$RG" -n "$FUNC" \
  --query "[?name=='API_KEY'].value | [0]" -o tsv 2>/dev/null || true)
[ -n "$API_KEY" ] || err "could not read API_KEY from $RG/$FUNC — check 'az account show' and that the Function App exists"
ok "got API_KEY (${#API_KEY} chars)"

# 4. Write into the app's UserDefaults plist. plutil handles plist creation if
#    the file doesn't exist yet (first launch).
mkdir -p "$(dirname "$PREFS_PLIST")"
if [ ! -f "$PREFS_PLIST" ]; then
  printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' \
    > "$PREFS_PLIST"
fi
plutil -replace serverURL -string "$SERVER_URL" "$PREFS_PLIST"
plutil -replace apiKey    -string "$API_KEY"    "$PREFS_PLIST"
ok "wrote serverURL = $SERVER_URL"
ok "wrote apiKey    = (hidden)"

# 5. UserDefaults is cached in-process. If the app is already running, we need
#    a relaunch for the values to be picked up.
log "relaunching the app so it picks up the new defaults ..."
xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch    "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null
ok "ClaudeLifter relaunched. Open Settings → Sync Status to confirm."
echo
echo "On next sync, watch traffic with:"
echo "  az monitor metrics list \\"
echo "    --resource \"/subscriptions/\$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.Web/sites/$FUNC\" \\"
echo "    --metric FunctionExecutionCount --interval PT5M --aggregation Total"
