#!/bin/bash

# Narrow, repeatable migration of the worker's system caffeinate job.
set -euo pipefail

if [[ "$(id -u)" != 0 ]]; then
  echo "ERROR: Run this migration with sudo."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_LABEL="local.xcode-worker.caffeinate"
NEW_PLIST="/Library/LaunchDaemons/$NEW_LABEL.plist"
SOURCE_PLIST="$ROOT/launchd/$NEW_LABEL.plist"
OLD_LABEL="one.0777.xcode-worker.caffeinate"
OLD_PLIST="/Library/LaunchDaemons/$OLD_LABEL.plist"

expected_job() {
  local path="$1" label="$2"
  [[ -f "$path" && ! -L "$path" ]] &&
    [[ "$(plutil -extract Label raw -o - "$path" 2>/dev/null)" == "$label" ]] &&
    [[ "$(plutil -extract ProgramArguments.0 raw -o - "$path" 2>/dev/null)" == "/usr/bin/caffeinate" ]] &&
    [[ "$(plutil -extract ProgramArguments.1 raw -o - "$path" 2>/dev/null)" == "-s" ]] &&
    [[ "$(plutil -extract ProgramArguments.2 raw -o - "$path" 2>/dev/null)" == "-i" ]] &&
    ! plutil -extract ProgramArguments.3 raw -o - "$path" >/dev/null 2>&1 &&
    [[ "$(plutil -extract RunAtLoad raw -o - "$path" 2>/dev/null)" == "true" ]] &&
    [[ "$(plutil -extract KeepAlive raw -o - "$path" 2>/dev/null)" == "true" ]]
}

if ! expected_job "$SOURCE_PLIST" "$NEW_LABEL"; then
  echo "ERROR: Repository caffeinate plist is not the expected job."
  exit 1
fi

if [[ -e "$OLD_PLIST" || -L "$OLD_PLIST" ]]; then
  if ! expected_job "$OLD_PLIST" "$OLD_LABEL" ||
     [[ "$(stat -f %u "$OLD_PLIST")" != 0 ]]; then
    echo "ERROR: Legacy caffeinate plist differs from the expected root-owned job."
    exit 1
  fi
fi

if [[ -e "$NEW_PLIST" || -L "$NEW_PLIST" ]]; then
  if ! expected_job "$NEW_PLIST" "$NEW_LABEL" ||
     [[ "$(stat -f %u "$NEW_PLIST")" != 0 ]]; then
    echo "ERROR: Generic caffeinate plist path is occupied by an unexpected job."
    exit 1
  fi
fi

old_job="$(launchctl print "system/$OLD_LABEL" 2>/dev/null || true)"
if [[ -n "$old_job" ]] &&
   { [[ ! -f "$OLD_PLIST" ]] || ! grep -Fq "path = $OLD_PLIST" <<< "$old_job"; }; then
  echo "ERROR: Legacy caffeinate job is loaded from an unexpected path."
  exit 1
fi

new_job="$(launchctl print "system/$NEW_LABEL" 2>/dev/null || true)"
if [[ -n "$new_job" ]] && ! grep -Fq "path = $NEW_PLIST" <<< "$new_job"; then
  echo "ERROR: Generic caffeinate label is loaded from an unexpected path."
  exit 1
fi

install -o root -g wheel -m 644 "$SOURCE_PLIST" "$NEW_PLIST"
plutil -lint "$NEW_PLIST"

if [[ -n "$new_job" ]]; then
  launchctl bootout "system/$NEW_LABEL"
fi
launchctl bootstrap system "$NEW_PLIST"
new_job="$(launchctl print "system/$NEW_LABEL" 2>/dev/null || true)"
if [[ "$new_job" != *"state = running"* ]]; then
  echo "ERROR: Generic caffeinate job did not start; legacy job was retained."
  exit 1
fi

# Keep the old job until its replacement has been verified as running.
if [[ -n "$old_job" ]]; then
  launchctl bootout "system/$OLD_LABEL"
fi
if [[ -f "$OLD_PLIST" ]]; then
  rm -- "$OLD_PLIST"
fi

if launchctl print "system/$OLD_LABEL" >/dev/null 2>&1 ||
   [[ -e "$OLD_PLIST" || -L "$OLD_PLIST" ]]; then
  echo "ERROR: Legacy caffeinate job or plist remains."
  exit 1
fi

echo "Generic caffeinate LaunchDaemon is running; legacy job is absent."
