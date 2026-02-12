#!/bin/bash
set -e

LOG_PREFIX="[gh-not-sync]"
LOCK_FILE="$HOME/.local/state/gh-not/sync.lock"

# Prevent overlapping syncs
if [ -f "$LOCK_FILE" ]; then
  lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
  if kill -0 "$lock_pid" 2>/dev/null; then
    echo "$LOG_PREFIX Skipping: previous sync (PID $lock_pid) still running"
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi

trap 'rm -f "$LOCK_FILE"' EXIT
echo $$ > "$LOCK_FILE"

echo "$LOG_PREFIX Starting sync at $(date)"

if ! command -v gh >/dev/null 2>&1; then
  echo "$LOG_PREFIX ERROR: gh not found in PATH" >&2
  exit 1
fi

if ! gh not sync -v 4 -f apply; then
  echo "$LOG_PREFIX ERROR: sync failed at $(date)" >&2
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier \
      -title "⚠️ gh-not" \
      -subtitle "Sync Error" \
      -message "gh-not sync failed! Check ~/.local/log/gh-not-sync.log" \
      -sound default \
      -group "gh-not-sync"
  else
    osascript -e 'display notification "gh-not sync failed! Check ~/.local/log/gh-not-sync.log" with title "⚠️ gh-not" subtitle "Sync Error"'
  fi
  exit 1
fi

echo "$LOG_PREFIX Sync completed at $(date)"
