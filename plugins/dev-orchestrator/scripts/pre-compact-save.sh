#!/usr/bin/env bash
# pre-compact-save.sh
# Runs before context compaction to persist session state.
# Appends compaction markers to active session logs and updates manifest timestamps.

set -euo pipefail

STATE_DIR="${PWD}/.dev-orchestrator"
MANIFEST="${STATE_DIR}/manifest.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Exit silently if no dev-orchestrator state exists
if [ ! -f "$MANIFEST" ]; then
  exit 0
fi

# Update manifest: set updated timestamp on the latest session entry
# Uses a lightweight approach — appends compaction count if jq is available
if command -v jq &>/dev/null; then
  TEMP=$(mktemp)
  jq --arg ts "$TIMESTAMP" '
    .updated = $ts |
    if (.sessions | length) > 0 then
      .sessions[-1].lastActive = $ts |
      .sessions[-1].compactions = ((.sessions[-1].compactions // 0) + 1)
    else . end
  ' "$MANIFEST" > "$TEMP" && mv "$TEMP" "$MANIFEST"
fi

# Append compaction marker to all status.md session logs
for status_file in "$STATE_DIR"/*/status.md; do
  [ -f "$status_file" ] || continue

  # Only append if the file has a Session Log section
  if grep -q "## Session Log" "$status_file" 2>/dev/null; then
    printf '\n### %s [COMPACTION]\n- Context compacted. Progress preserved in state files.\n' "$TIMESTAMP" >> "$status_file"
  fi
done

exit 0
