#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: This bootstrap currently expects Apple Silicon."
  exit 1
fi

EXPECTED_USER="${XCODE_WORKER_USER:-worker}"
if [[ "$(id -un)" != "$EXPECTED_USER" ]]; then
  echo "ERROR: Run this as the configured worker user ($EXPECTED_USER)."
  exit 1
fi

echo "==> xcode-worker bootstrap"

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is not installed."
  echo "Install Homebrew first, then rerun bootstrap."
  exit 1
fi

eval "$(/opt/homebrew/bin/brew shellenv)"

# Persist Homebrew environment
touch "$HOME/.zprofile"

if ! grep -q '/opt/homebrew/bin/brew shellenv' "$HOME/.zprofile"; then
  echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> "$HOME/.zprofile"
fi

echo "==> Installing Homebrew dependencies"
brew bundle --file="$ROOT/Brewfile"

# 1Password service account is the only local Apple bootstrap credential.
echo "==> Configuring 1Password service account"
OP_CONFIG_DIR="$HOME/.config/xcode-worker"
OP_TOKEN_FILE="$OP_CONFIG_DIR/1password-service-account-token"
OP_VAULT="${XCODE_WORKER_OP_VAULT:-automation-apple}"
if [[ ! "$OP_VAULT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "ERROR: XCODE_WORKER_OP_VAULT must be a simple 1Password vault name."
  exit 1
fi
umask 077
mkdir -p "$OP_CONFIG_DIR"
if [[ ! -d "$OP_CONFIG_DIR" || -L "$OP_CONFIG_DIR" || ! -O "$OP_CONFIG_DIR" ]]; then
  echo "ERROR: 1Password configuration directory must be owned by the worker and not be a symlink."
  exit 1
fi
chmod 700 "$OP_CONFIG_DIR"

if [[ -e "$OP_TOKEN_FILE" || -L "$OP_TOKEN_FILE" ]]; then
  if [[ ! -f "$OP_TOKEN_FILE" || -L "$OP_TOKEN_FILE" || ! -O "$OP_TOKEN_FILE" ]]; then
    echo "ERROR: Existing 1Password token path is not a worker-owned regular file."
    exit 1
  fi
  chmod 600 "$OP_TOKEN_FILE"
else
  if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    if [[ ! -t 0 ]]; then
      echo "ERROR: Set OP_SERVICE_ACCOUNT_TOKEN or run interactively to supply the token."
      exit 1
    fi
    read -r -s -p "1Password Service Account token: " OP_SERVICE_ACCOUNT_TOKEN
    echo
  fi
  if [[ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]]; then
    echo "ERROR: 1Password Service Account token is empty."
    exit 1
  fi
  ( set -C; printf '%s\n' "$OP_SERVICE_ACCOUNT_TOKEN" > "$OP_TOKEN_FILE" )
  chmod 600 "$OP_TOKEN_FILE"
fi
unset OP_SERVICE_ACCOUNT_TOKEN

if [[ ! -s "$OP_TOKEN_FILE" ]]; then
  echo "ERROR: 1Password Service Account token file is empty."
  exit 1
fi

# Automation signing keychain
echo "==> Configuring automation signing keychain"

SIGNING_KEYCHAIN="xcode-worker.keychain"
SIGNING_KEYCHAIN_PATH="$HOME/Library/Keychains/xcode-worker.keychain-db"

if ! KEYCHAIN_PASSWORD="$(OP_SERVICE_ACCOUNT_TOKEN="$(<"$OP_TOKEN_FILE")" op read "op://$OP_VAULT/xcode-worker-keychain/password" 2>/dev/null)" || [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  echo "ERROR: Cannot read automation keychain password from 1Password."
  exit 1
fi

if [[ ! -f "$SIGNING_KEYCHAIN_PATH" ]]; then
  security create-keychain \
    -p "$KEYCHAIN_PASSWORD" \
    "$SIGNING_KEYCHAIN"
fi

security unlock-keychain \
  -p "$KEYCHAIN_PASSWORD" \
  "$SIGNING_KEYCHAIN"
unset KEYCHAIN_PASSWORD

security set-keychain-settings \
  -lut 21600 \
  "$SIGNING_KEYCHAIN"

# Add the signing keychain without replacing other keychains in the user search list.
keychains=()
signing_keychain_listed=false
keychain_list="$(security list-keychains -d user)"
while IFS= read -r keychain; do
  keychain="${keychain#"${keychain%%[![:space:]]*}"}"
  keychain="${keychain#\"}"
  keychain="${keychain%\"}"
  [[ -z "$keychain" ]] && continue
  keychains+=("$keychain")
  if [[ "$keychain" == "$SIGNING_KEYCHAIN_PATH" ]]; then
    signing_keychain_listed=true
  fi
done <<< "$keychain_list"

if [[ "$signing_keychain_listed" == false ]]; then
  security list-keychains -d user -s "${keychains[@]}" "$SIGNING_KEYCHAIN_PATH"
fi

# caffeinate LaunchDaemon
echo "==> Installing caffeinate LaunchDaemon"
sudo "$ROOT/migrate-caffeinate-launchd.sh"

# Power configuration
echo "==> Configuring power management"

sudo pmset -b \
  sleep 1 \
  displaysleep 2 \
  womp 0 \
  powernap 1

sudo pmset -c \
  sleep 0 \
  displaysleep 2 \
  womp 1 \
  powernap 0

# tailscaled
echo "==> Starting tailscaled as system service"

sudo brew services restart tailscale

# Time Machine exclusions.
# Safe even before a destination is configured.
echo "==> Configuring Time Machine exclusions"

sudo tmutil addexclusion -p \
  "$HOME/Library/Developer/Xcode/DerivedData"

sudo tmutil addexclusion -p \
  "$HOME/Library/Developer/CoreSimulator"

sudo tmutil addexclusion -p \
  /Library/Caches

echo
echo "Bootstrap automation complete."
echo
echo "Manual steps are still required:"
echo "  - Xcode + required simulator runtime"
echo "  - Remote Login"
echo "  - Screen Sharing"
echo "  - Tailscale authentication"
echo "  - restore Apple Development identity and profiles with the readonly Fastlane lane"
echo "  - Codex ChatGPT authentication"
echo "  - Time Machine destination"
echo
echo "Finish the README checklist, then run:"
echo "  $ROOT/verify.sh"
