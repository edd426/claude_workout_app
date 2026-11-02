#!/bin/bash
# Create the Entra ID app that signs claude.ai into the remote workout MCP — issue #162.
# Adapted from personal_memory/infra/scripts/setup-entra-app.sh.
#
# Run once. Prints ids only; the client secret goes straight into the macOS
# Keychain (service claudelifter-mcp, account entra-client-secret) and is never
# echoed. infra/mcp/scripts/deploy-remote.sh reads it from there.
#
# Rotate the secret before it expires (1 year):
#   az ad app credential reset --id <appId> --display-name claudelifter-mcp --years 1 --query password -o tsv \
#     | xargs -I{} security add-generic-password -U -s claudelifter-mcp -a entra-client-secret -w {}
#   then rerun deploy-remote.sh.

set -euo pipefail

APP_NAME="ClaudeLifter Workout MCP"
SCOPE_VALUE="workout.access"
KEYCHAIN_SERVICE="claudelifter-mcp"

# Only Claude's callbacks. This list is the real redirect control: anyone can call
# login.microsoftonline.com directly, bypassing the proxy's own check.
REPLY_URLS=(
  "https://claude.ai/api/mcp/auth_callback"
  "https://claude.com/api/mcp/auth_callback"
)

if az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv | grep -q .; then
  echo "An app named \"$APP_NAME\" already exists; not creating another." >&2
  exit 1
fi

echo "Creating app registration: $APP_NAME"
APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "${REPLY_URLS[@]}" \
  --query appId -o tsv)
OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

echo "Exposing api://$APP_ID/$SCOPE_VALUE (v2 access tokens)"
SCOPE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
az ad app update --id "$APP_ID" --identifier-uris "api://$APP_ID"
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"api\":{\"requestedAccessTokenVersion\":2,\"oauth2PermissionScopes\":[{\"id\":\"$SCOPE_ID\",\"value\":\"$SCOPE_VALUE\",\"type\":\"User\",\"isEnabled\":true,\"adminConsentDisplayName\":\"Use the workout MCP\",\"adminConsentDescription\":\"Read workout data and queue changes for approval in the ClaudeLifter app\",\"userConsentDisplayName\":\"Use the workout MCP\",\"userConsentDescription\":\"Read your workout data and queue changes for your approval\"}]}}" \
  --output none

echo "Creating service principal with assignment required"
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
az ad sp update --id "$SP_ID" --set appRoleAssignmentRequired=true

USER_OID=$(az ad signed-in-user show --query id -o tsv)
echo "Assigning the signed-in user ($USER_OID)"
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignedTo" \
  --headers "Content-Type=application/json" \
  --body "{\"principalId\":\"$USER_OID\",\"resourceId\":\"$SP_ID\",\"appRoleId\":\"00000000-0000-0000-0000-000000000000\"}" \
  --output none

echo "Creating a 1-year client secret into the Keychain ($KEYCHAIN_SERVICE / entra-client-secret)"
SECRET=$(az ad app credential reset --id "$APP_ID" --display-name claudelifter-mcp --years 1 --query password -o tsv)
security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a entra-client-secret -w "$SECRET"
unset SECRET
security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a entra-client-id -w "$APP_ID"

echo
echo "ENTRA_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "ENTRA_CLIENT_ID=$APP_ID"
echo "ALLOWED_OIDS=$USER_OID"
