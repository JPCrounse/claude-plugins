#!/usr/bin/env bash
# pre-compact-save.sh
# Runs before context compaction to persist session state.
# Appends compaction markers to whichever logs the active workflow uses
# (status.md per topic in supervised modes; one-shot-log.md in one-shot mode).

set -euo pipefail

STATE_DIR="${PWD}/.dev-orchestrator"
MANIFEST="${STATE_DIR}/manifest.json"
ONE_SHOT_LOG="${STATE_DIR}/one-shot-log.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Exit silently if no dev-orchestrator state exists
if [ ! -f "$MANIFEST" ]; then
  exit 0
fi

# Determine executionMode — defaults to "speed" if jq is unavailable (defensive fallback for environments without jq)
EXECUTION_MODE="speed"
if command -v jq &>/dev/null; then
  EXECUTION_MODE=$(jq -r '.executionMode // "speed"' "$MANIFEST" 2>/dev/null || echo "speed")
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

# Mode-specific log append
case "$EXECUTION_MODE" in
  "one-shot")
    # In one-shot mode, status.md per topic does not exist.
    # Append a single compaction marker to one-shot-log.md if it exists.
    if [ -f "$ONE_SHOT_LOG" ]; then
      printf '\n### %s [COMPACTION]\n- Context compacted during one-shot workflow. The running agent will re-read one-shot-log.md to identify resumption point.\n' "$TIMESTAMP" >> "$ONE_SHOT_LOG"
    fi
    ;;
  *)
    # Supervised modes (speed, efficiency, deferred): append to each topic's status.md
    for status_file in "$STATE_DIR"/*/status.md; do
      [ -f "$status_file" ] || continue

      # Only append if the file has a Session Log section
      if grep -q "## Session Log" "$status_file" 2>/dev/null; then
        printf '\n### %s [COMPACTION]\n- Context compacted. Progress preserved in state files.\n' "$TIMESTAMP" >> "$status_file"
      fi
    done
    ;;
esac

exit 0
