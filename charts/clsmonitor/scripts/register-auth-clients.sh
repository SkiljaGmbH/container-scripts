#!/bin/sh
set -eu

# Registers all OAuth/OIDC clients required by the Skilja Helm charts
# against the Skilja auth server (IdentityServer/Duende + OpenIddict).
#
# Generic, parametrized version: permissions (and, for confidential
# clients, optional redirect URIs) are passed in by the caller (each
# chart's job env / call site), NOT hardcoded per chart inside this
# script. This avoids needing a new function every time a chart's spec
# differs from another chart's.
#
# Uses only BusyBox built-ins (wget, sed) - no curl/jq needed.

: "${AUTH_SERVER_URL:?AUTH_SERVER_URL is required (e.g. https://my.domain.com/auth)}"
: "${ADMIN_CLIENT_ID:?ADMIN_CLIENT_ID is required}"
: "${ADMIN_CLIENT_SECRET:?ADMIN_CLIENT_SECRET is required}"

command -v wget >/dev/null 2>&1 || { echo "wget is required but not installed." >&2; exit 1; }

TOKEN_RESPONSE=$(wget -q -O - \
  --post-data="client_id=$ADMIN_CLIENT_ID&client_secret=$ADMIN_CLIENT_SECRET&grant_type=client_credentials" \
  "$AUTH_SERVER_URL/connect/token") || {
  echo "Failed to reach $AUTH_SERVER_URL/connect/token" >&2
  exit 1
}

ACCESS_TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to obtain access token. Server response:" >&2
  echo "$TOKEN_RESPONSE" >&2
  exit 1
fi

# --- Helpers -----------------------------------------------------------

csv_to_json_array() {
  csv="$1"
  if [ -z "$csv" ]; then
    printf '[]'
    return 0
  fi
  printf '["%s"]' "$(printf '%s' "$csv" | sed 's/,/","/g')"
}

client_exists() {
  wget -q -O /dev/null \
    --header="Authorization: Bearer $ACCESS_TOKEN" \
    "$AUTH_SERVER_URL/applications/$1"
}

post_client() {
  client_id=$1
  payload=$2
  response_file=$(mktemp)
  if wget -q -O "$response_file" \
    --header="Authorization: Bearer $ACCESS_TOKEN" \
    --header="Content-Type: application/json" \
    --post-data="$payload" \
    "$AUTH_SERVER_URL/applications"; then
    echo "Successfully registered $client_id"
    rm -f "$response_file"
    return 0
  else
    echo "Failed to register $client_id. Server response:" >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    return 1
  fi
}

# --- Generic registration functions (parametrized, chart-agnostic) -----

# Confidential, machine-to-machine and/or interactive server client.
# Usage: register_confidential_client <client_id> <client_secret> <permissions_csv> [redirect_uri] [post_logout_uri]
#
# redirect_uri / post_logout_uri are OPTIONAL: pass them for confidential
# clients that use an interactive authorization_code flow (e.g. aiserver -
# a confidential server-side web app). Plain M2M server clients
# (ClsWebDesignerServer, ClsOLMonitorServer, ...) simply omit these two
# args and get empty arrays.
register_confidential_client() {
  client_id=$1
  client_secret=$2
  permissions_csv=$3
  redirect_uri=${4:-}
  post_logout_uri=${5:-}

  if client_exists "$client_id"; then
    echo "Client $client_id already exists. Skipping..."
    return 0
  fi

  permissions_json=$(csv_to_json_array "$permissions_csv")
  redirect_json=$(csv_to_json_array "$redirect_uri")
  post_logout_json=$(csv_to_json_array "$post_logout_uri")

  payload=$(cat <<EOF
{
  "clientId": "$client_id",
  "clientSecret": "$client_secret",
  "clientType": "confidential",
  "permissions": $permissions_json,
  "redirectUris": $redirect_json,
  "postLogoutRedirectUris": $post_logout_json
}
EOF
)
  post_client "$client_id" "$payload"
}

# Public, browser-based web client (Authorization Code flow, no secret).
# Usage: register_public_client <client_id> <redirect_uri> <post_logout_uri> <permissions_csv>
register_public_client() {
  client_id=$1
  redirect_uri=$2
  post_logout_uri=$3
  permissions_csv=$4

  if client_exists "$client_id"; then
    echo "Client $client_id already exists. Skipping..."
    return 0
  fi

  permissions_json=$(csv_to_json_array "$permissions_csv")
  redirect_json=$(csv_to_json_array "$redirect_uri")
  post_logout_json=$(csv_to_json_array "$post_logout_uri")

  payload=$(cat <<EOF
{
  "clientId": "$client_id",
  "clientSecret": null,
  "clientType": "public",
  "permissions": $permissions_json,
  "redirectUris": $redirect_json,
  "postLogoutRedirectUris": $post_logout_json
}
EOF
)
  post_client "$client_id" "$payload"
}

# --- MAIN EXECUTION -----------------------------------------------------
# Each chart section below is gated by its own AUTOCREATE_* flag, mirroring
# the `autoCreateAuthClients: true/false` value in that chart's values.yaml.
# Permissions are spelled out explicitly per chart/spec - do not centralize
# them into a shared constant, since each chart's official doc differs.

FAILED=0

# --- aiserver ---
# Confidential client using only the interactive Authorization Code flow
# (server-side web app pattern: client secret + browser redirect). The
# client_credentials grant was intentionally removed - this client no
# longer needs machine-to-machine token requests.
if [ "${AUTOCREATE_AISERVER:-false}" = "true" ]; then
  : "${AISERVER_CLIENT_ID:?AISERVER_CLIENT_ID is required}"
  : "${AISERVER_CLIENT_SECRET:?AISERVER_CLIENT_SECRET is required}"
  : "${AISERVER_REDIRECT_URI:?AISERVER_REDIRECT_URI is required}"
  register_confidential_client "$AISERVER_CLIENT_ID" "$AISERVER_CLIENT_SECRET" \
    "ept:authorization,gt:authorization_code,rst:code,scp:roles,ept:token,scp:profile,gt:refresh_token,ept:end_session" \
    "$AISERVER_REDIRECT_URI/signin-oidc" "$AISERVER_REDIRECT_URI/signout-callback-oidc" || FAILED=1
fi

# --- classification-designer ---
if [ "${AUTOCREATE_CLSDESIGNER:-false}" = "true" ]; then
  : "${CLSDESIGNER_WEBAPP_CLIENT_ID:?CLSDESIGNER_WEBAPP_CLIENT_ID is required}"
  : "${CLSDESIGNER_WEBAPP_REDIRECT_URI:?CLSDESIGNER_WEBAPP_REDIRECT_URI is required}"
  register_public_client "$CLSDESIGNER_WEBAPP_CLIENT_ID" "$CLSDESIGNER_WEBAPP_REDIRECT_URI" "$CLSDESIGNER_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1

  : "${CLSDESIGNER_SERVER_CLIENT_ID:?CLSDESIGNER_SERVER_CLIENT_ID is required}"
  : "${CLSDESIGNER_SERVER_CLIENT_SECRET:?CLSDESIGNER_SERVER_CLIENT_SECRET is required}"
  register_confidential_client "$CLSDESIGNER_SERVER_CLIENT_ID" "$CLSDESIGNER_SERVER_CLIENT_SECRET" \
    "gt:client_credentials,ept:introspection,scp:email,scp:roles,ept:token,scp:profile" || FAILED=1
fi

# --- classification-monitor ---
if [ "${AUTOCREATE_CLSMONITOR:-false}" = "true" ]; then
  : "${CLSMONITOR_WEBAPP_CLIENT_ID:?CLSMONITOR_WEBAPP_CLIENT_ID is required}"
  : "${CLSMONITOR_WEBAPP_REDIRECT_URI:?CLSMONITOR_WEBAPP_REDIRECT_URI is required}"
  # Per official docs: Authorization Code only, Scopes = Profile only,
  # no Roles, no Introspection, no end_session listed.
  # gt:refresh_token is required nevertheless: the admin UI only shows a
  # client as "Authorization Code" if gt:refresh_token is present.
  register_public_client "$CLSMONITOR_WEBAPP_CLIENT_ID" "$CLSMONITOR_WEBAPP_REDIRECT_URI" "$CLSMONITOR_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,ept:token,scp:profile,gt:refresh_token" || FAILED=1

  : "${CLSMONITOR_SERVER_CLIENT_ID:?CLSMONITOR_SERVER_CLIENT_ID is required}"
  : "${CLSMONITOR_SERVER_CLIENT_SECRET:?CLSMONITOR_SERVER_CLIENT_SECRET is required}"
  # Per official docs: Client Credentials only, Introspection = Yes,
  # Scopes = Profile, Email, Roles.
  register_confidential_client "$CLSMONITOR_SERVER_CLIENT_ID" "$CLSMONITOR_SERVER_CLIENT_SECRET" \
    "gt:client_credentials,ept:introspection,scp:email,scp:roles,ept:token,scp:profile" || FAILED=1
fi

# --- extraction-designer ---
if [ "${AUTOCREATE_EXTRDESIGNER:-false}" = "true" ]; then
  : "${EXTRDESIGNER_WEBAPP_CLIENT_ID:?EXTRDESIGNER_WEBAPP_CLIENT_ID is required}"
  : "${EXTRDESIGNER_WEBAPP_REDIRECT_URI:?EXTRDESIGNER_WEBAPP_REDIRECT_URI is required}"
  register_public_client "$EXTRDESIGNER_WEBAPP_CLIENT_ID" "$EXTRDESIGNER_WEBAPP_REDIRECT_URI" "$EXTRDESIGNER_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1

  : "${EXTRDESIGNER_SERVER_CLIENT_ID:?EXTRDESIGNER_SERVER_CLIENT_ID is required}"
  : "${EXTRDESIGNER_SERVER_CLIENT_SECRET:?EXTRDESIGNER_SERVER_CLIENT_SECRET is required}"
  register_confidential_client "$EXTRDESIGNER_SERVER_CLIENT_ID" "$EXTRDESIGNER_SERVER_CLIENT_SECRET" \
    "gt:client_credentials,ept:introspection,scp:email,scp:roles,ept:token,scp:profile" || FAILED=1
fi

# --- extraction-monitor ---
if [ "${AUTOCREATE_EXTRMONITOR:-false}" = "true" ]; then
  : "${EXTRMONITOR_WEBAPP_CLIENT_ID:?EXTRMONITOR_WEBAPP_CLIENT_ID is required}"
  : "${EXTRMONITOR_WEBAPP_REDIRECT_URI:?EXTRMONITOR_WEBAPP_REDIRECT_URI is required}"
  # Authorization Code, Scope Profile only (same as classification-monitor).
  # gt:refresh_token is required, otherwise the admin UI does not show the client as Authorization Code.
  register_public_client "$EXTRMONITOR_WEBAPP_CLIENT_ID" "$EXTRMONITOR_WEBAPP_REDIRECT_URI" "$EXTRMONITOR_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,ept:token,scp:profile,gt:refresh_token" || FAILED=1

  : "${EXTRMONITOR_SERVER_CLIENT_ID:?EXTRMONITOR_SERVER_CLIENT_ID is required}"
  : "${EXTRMONITOR_SERVER_CLIENT_SECRET:?EXTRMONITOR_SERVER_CLIENT_SECRET is required}"
  register_confidential_client "$EXTRMONITOR_SERVER_CLIENT_ID" "$EXTRMONITOR_SERVER_CLIENT_SECRET" \
    "gt:client_credentials,ept:introspection,scp:email,scp:roles,ept:token,scp:profile" || FAILED=1
fi

# --- batchreview ---
# Per official docs: public client, Authorization Code only, no introspection,
# scopes Activities, Activities Unattended, Profile (interactive).
# Redirect URI and post-logout URI are both the Batch Review URL (case sensitive).
# ept:end_session replaces the older ept:logout used in the auth chart's seed file
# (OpenIddict 5+ naming, same as all other clients in this script).
if [ "${AUTOCREATE_BATCHREVIEW:-false}" = "true" ]; then
  : "${BATCHREVIEW_WEBAPP_CLIENT_ID:?BATCHREVIEW_WEBAPP_CLIENT_ID is required}"
  : "${BATCHREVIEW_WEBAPP_REDIRECT_URI:?BATCHREVIEW_WEBAPP_REDIRECT_URI is required}"
  register_public_client "$BATCHREVIEW_WEBAPP_CLIENT_ID" "$BATCHREVIEW_WEBAPP_REDIRECT_URI" "$BATCHREVIEW_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,scp:interactive,scp:unattended,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1
fi

# --- fieldreview ---
# Same client spec as batchreview (public, Authorization Code, Activities,
# Activities Unattended, Profile).
if [ "${AUTOCREATE_FIELDREVIEW:-false}" = "true" ]; then
  : "${FIELDREVIEW_WEBAPP_CLIENT_ID:?FIELDREVIEW_WEBAPP_CLIENT_ID is required}"
  : "${FIELDREVIEW_WEBAPP_REDIRECT_URI:?FIELDREVIEW_WEBAPP_REDIRECT_URI is required}"
  register_public_client "$FIELDREVIEW_WEBAPP_CLIENT_ID" "$FIELDREVIEW_WEBAPP_REDIRECT_URI" "$FIELDREVIEW_WEBAPP_REDIRECT_URI" \
    "ept:authorization,gt:authorization_code,rst:code,scp:interactive,scp:unattended,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1
fi

# --- validationservice ---
# Per official docs: public client (no secret), Authorization Code only, no introspection,
# scopes Roles + Profile. Redirect <base>/signin-oidc, post-logout <base>/signout-callback-oidc,
# all lowercase. gt:refresh_token / ept:end_session as for the other Authorization Code clients
# (admin UI shows "Authorization Code" only with refresh_token, end_session is needed for logout).
if [ "${AUTOCREATE_VALIDATIONSERVICE:-false}" = "true" ]; then
  : "${VALIDATIONSERVICE_CLIENT_ID:?VALIDATIONSERVICE_CLIENT_ID is required}"
  : "${VALIDATIONSERVICE_BASE_URI:?VALIDATIONSERVICE_BASE_URI is required}"
  register_public_client "$VALIDATIONSERVICE_CLIENT_ID" \
    "$VALIDATIONSERVICE_BASE_URI/signin-oidc" "$VALIDATIONSERVICE_BASE_URI/signout-callback-oidc" \
    "ept:authorization,gt:authorization_code,rst:code,scp:roles,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1
fi

# --- lookupservice ---
# Same client spec as validationservice.
if [ "${AUTOCREATE_LOOKUPSERVICE:-false}" = "true" ]; then
  : "${LOOKUPSERVICE_CLIENT_ID:?LOOKUPSERVICE_CLIENT_ID is required}"
  : "${LOOKUPSERVICE_BASE_URI:?LOOKUPSERVICE_BASE_URI is required}"
  register_public_client "$LOOKUPSERVICE_CLIENT_ID" \
    "$LOOKUPSERVICE_BASE_URI/signin-oidc" "$LOOKUPSERVICE_BASE_URI/signout-callback-oidc" \
    "ept:authorization,gt:authorization_code,rst:code,scp:roles,ept:token,scp:profile,gt:refresh_token,ept:end_session" || FAILED=1
fi

exit $FAILED
