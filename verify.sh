#!/bin/bash

set -u

PASS=0
FAIL=0
WARN=0

pass() {
  printf '✓ %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf '✗ %s\n' "$1"
  FAIL=$((FAIL + 1))
}

warn() {
  printf '! %s\n' "$1"
  WARN=$((WARN + 1))
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo "=== xcode-worker verification ==="
echo

# Identity
EXPECTED_HOSTNAME="${XCODE_WORKER_HOSTNAME:-xcode-worker}"
EXPECTED_USER="${XCODE_WORKER_USER:-worker}"
if [[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]]; then
  pass "hostname = $EXPECTED_HOSTNAME"
else
  fail "hostname is $(hostname), expected $EXPECTED_HOSTNAME"
fi

if [[ "$(id -un)" == "$EXPECTED_USER" ]]; then
  pass "user = $EXPECTED_USER"
else
  fail "user is $(id -un), expected $EXPECTED_USER"
fi

# Xcode
if [[ "$(xcode-select -p 2>/dev/null)" == "/Applications/Xcode.app/Contents/Developer" ]]; then
  pass "Xcode selected"
else
  fail "Xcode developer directory is not selected correctly"
fi

if xcodebuild -version >/dev/null 2>&1; then
  pass "$(xcodebuild -version | tr '\n' ' ')"
else
  fail "xcodebuild unavailable"
fi

if xcrun simctl list runtimes 2>/dev/null | grep -q 'iOS'; then
  pass "iOS simulator runtime installed"
else
  fail "iOS simulator runtime missing"
fi

# CLI tools
for cmd in brew git gh node npm codex fastlane op tmux nano tailscale; do
  if command_exists "$cmd"; then
    pass "$cmd available: $(command -v "$cmd")"
  else
    fail "$cmd missing"
  fi
done

# Codex
if codex login status >/dev/null 2>&1; then
  pass "Codex authenticated"
else
  fail "Codex not authenticated"
fi

# Tailscale
if pgrep -x tailscaled >/dev/null 2>&1; then
  pass "tailscaled running"
else
  fail "tailscaled not running"
fi

if tailscale ip -4 >/dev/null 2>&1 && [[ -n "$(tailscale ip -4 2>/dev/null)" ]]; then
  pass "Tailscale connected: $(tailscale ip -4)"
else
  fail "Tailscale not connected"
fi

# Power daemon
CAFFEINATE_LABEL="local.xcode-worker.caffeinate"
CAFFEINATE_PLIST="/Library/LaunchDaemons/$CAFFEINATE_LABEL.plist"

if [[ -f "$CAFFEINATE_PLIST" ]] &&
   [[ "$(plutil -extract Label raw -o - "$CAFFEINATE_PLIST" 2>/dev/null)" == "$CAFFEINATE_LABEL" ]]; then
  pass "generic caffeinate LaunchDaemon plist installed"
else
  fail "generic caffeinate LaunchDaemon plist missing or invalid"
fi

if launchctl print "system/$CAFFEINATE_LABEL" 2>/dev/null | grep -q 'state = running'; then
  pass "generic caffeinate LaunchDaemon running"
else
  fail "generic caffeinate LaunchDaemon not running"
fi

if pgrep -x caffeinate >/dev/null 2>&1; then
  pass "caffeinate running"
else
  fail "caffeinate not running"
fi

if pmset -g assertions 2>/dev/null | grep -q "caffeinate command-line tool"; then
  pass "caffeinate power assertion active"
else
  fail "caffeinate power assertion missing"
fi

# Signing
SIGNING_KEYCHAIN="$HOME/Library/Keychains/xcode-worker.keychain-db"
FASTLANE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fastlane"
OP_CONFIG_DIR="$HOME/.config/xcode-worker"
OP_TOKEN_FILE="$OP_CONFIG_DIR/1password-service-account-token"
OP_VAULT="${XCODE_WORKER_OP_VAULT:-automation-apple}"
WORKER_UID="$(id -u)"

if [[ "$OP_VAULT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  pass "1Password vault name is valid"
else
  fail "XCODE_WORKER_OP_VAULT must be a simple 1Password vault name"
fi

if [[ -d "$OP_CONFIG_DIR" && ! -L "$OP_CONFIG_DIR" ]] &&
   [[ "$(stat -f %u "$OP_CONFIG_DIR" 2>/dev/null)" == "$WORKER_UID" ]] &&
   [[ "$(stat -f %Lp "$OP_CONFIG_DIR" 2>/dev/null)" == "700" ]]; then
  pass "1Password configuration directory is owned by worker with mode 0700"
else
  fail "1Password configuration directory missing or unsafe"
fi

TOKEN_SAFE=false
if [[ -f "$OP_TOKEN_FILE" && ! -L "$OP_TOKEN_FILE" && -r "$OP_TOKEN_FILE" && -s "$OP_TOKEN_FILE" ]] &&
   [[ "$(stat -f %u "$OP_TOKEN_FILE" 2>/dev/null)" == "$WORKER_UID" ]] &&
   [[ "$(stat -f %Lp "$OP_TOKEN_FILE" 2>/dev/null)" == "600" ]]; then
  TOKEN_SAFE=true
  pass "1Password Service Account token is owned, readable, nonempty, and mode 0600"
else
  fail "1Password Service Account token missing or unsafe"
fi

if [[ "$TOKEN_SAFE" == true ]] && command_exists op; then
  # Keep the token and every secret out of verification output.
  export OP_SERVICE_ACCOUNT_TOKEN="$(<"$OP_TOKEN_FILE")"
  if op whoami >/dev/null 2>&1; then
    pass "1Password Service Account authenticates"
  else
    fail "1Password Service Account authentication failed"
  fi
  if op vault get "$OP_VAULT" >/dev/null 2>&1; then
    pass "$OP_VAULT vault accessible"
  else
    fail "$OP_VAULT vault inaccessible"
  fi
  for field in \
    'fastlane-match/password' \
    'fastlane-match/repository' \
    'xcode-worker-keychain/password' \
    'app-store-connect/key_id' \
    'app-store-connect/issuer_id' \
    'app-store-connect/team_id' \
    'app-store-connect/private_key' \
    'development-apps/bundle_ids'
  do
    reference="op://$OP_VAULT/$field"
    if value="$(op read "$reference" 2>/dev/null)" && [[ -n "$value" ]]; then
      pass "1Password reference readable: $reference"
    else
      fail "1Password reference unavailable: $reference"
    fi
    unset value
  done
  unset OP_SERVICE_ACCOUNT_TOKEN
else
  fail "1Password secret checks skipped because CLI or safe token is unavailable"
fi

if command_exists fastlane && [[ -f "$FASTLANE_DIR/Fastfile" ]] &&
   (cd "$(dirname "$FASTLANE_DIR")" && fastlane list_development_apps >/dev/null 2>&1); then
  pass "declared development Bundle IDs are nonempty and valid"
else
  fail "development app inventory is unavailable or invalid"
fi

if [[ -f "$SIGNING_KEYCHAIN" ]]; then
  pass "automation signing keychain present"
else
  fail "automation signing keychain missing"
fi

if USER_KEYCHAINS="$(security list-keychains -d user 2>/dev/null)" && [[ -n "$USER_KEYCHAINS" ]]; then
  SIGNING_IN_SEARCH_LIST=false
  while IFS= read -r entry; do
    keychain_path="$(sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' <<< "$entry")"
    [[ -z "$keychain_path" ]] && continue
    if [[ -f "$keychain_path" && ( "$keychain_path" == *.keychain-db || "$keychain_path" == *.keychain ) ]]; then
      pass "user keychain search-list entry exists: $keychain_path"
    else
      fail "user keychain search-list entry is not an existing keychain path: $keychain_path"
    fi
    [[ "$keychain_path" == "$SIGNING_KEYCHAIN" ]] && SIGNING_IN_SEARCH_LIST=true
  done <<< "$USER_KEYCHAINS"
  if [[ "$SIGNING_IN_SEARCH_LIST" == true ]]; then
    pass "automation signing keychain is in the user search list"
  else
    fail "automation signing keychain is missing from the user search list"
  fi
else
  fail "user keychain search list is unavailable or empty"
fi

IDENTITIES="$(
  security find-identity \
    -v \
    -p codesigning \
    "$SIGNING_KEYCHAIN" \
    2>/dev/null
)"

if grep -q "Apple Development:" <<< "$IDENTITIES"; then
  pass "Apple Development identity available in automation keychain"
else
  fail "Apple Development identity missing from automation keychain"
fi

if [[ -f "$FASTLANE_DIR/Matchfile" ]] &&
   [[ -f "$FASTLANE_DIR/Fastfile" ]]; then
  pass "worker Fastlane workspace present"
else
  fail "worker Fastlane workspace missing"
fi

if [[ -f "$FASTLANE_DIR/Matchfile" ]] &&
   grep -Eq '^[[:space:]]*readonly\([[:space:]]*true[[:space:]]*\)' "$FASTLANE_DIR/Matchfile"; then
  pass "Matchfile is readonly by default"
else
  fail "Matchfile readonly default missing"
fi

# Time Machine exclusions
for path in \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/CoreSimulator" \
  "/Library/Caches"
do
  if tmutil isexcluded "$path" 2>/dev/null | grep -q '\[Excluded\]'; then
    pass "Time Machine excludes $path"
  else
    warn "Time Machine does not exclude $path"
  fi
done

echo
echo "=== Result ==="
echo "PASS: $PASS"
echo "WARN: $WARN"
echo "FAIL: $FAIL"

if (( FAIL > 0 )); then
  exit 1
fi
