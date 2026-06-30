#!/usr/bin/env bash
# pre-compact-save.sh
# Runs before context compaction to persist rpi-bugfix session state.
# rpi-bugfix is always single-bug and supervised, so there is no execution-mode
# branching: for each active bug under .rpi-bugfix/<JIRA-KEY>/ it appends a
# [COMPACTION] marker to session-notes.md and bumps the compaction counter in
# state.json (when jq is available). The marker tells a resuming agent that the
# system compacted and it should re-read state files before continuing.

set -euo pipefail

STATE_DIR="${PWD}/.rpi-bugfix"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Exit silently if no rpi-bugfix state exists (the common case — keeps the hook a no-op cost)
if [ ! -d "$STATE_DIR" ]; then
  exit 0
fi

# Update each bug's state.json (updated timestamp + compaction counter) when jq is available.
# Defensive: skip cleanly if jq is missing (e.g. a teammate's Git-Bash without jq).
if command -v jq &>/dev/null; then
  for state_file in "$STATE_DIR"/*/state.json; do
    [ -f "$state_file" ] || continue
    TEMP=$(mktemp)
    if jq --arg ts "$TIMESTAMP" '
      .updated = $ts |
      if (.sessions | length) > 0 then
        .sessions[-1].lastActive = $ts |
        .sessions[-1].compactions = ((.sessions[-1].compactions // 0) + 1)
      else . end
    ' "$state_file" > "$TEMP" 2>/dev/null; then
      mv "$TEMP" "$state_file"
    else
      rm -f "$TEMP"
    fi
  done
fi

# Append a compaction marker to each bug's session-notes.md.
for notes_file in "$STATE_DIR"/*/session-notes.md; do
  [ -f "$notes_file" ] || continue
  printf '\n### %s [COMPACTION]\n- Context compacted. Progress preserved in .rpi-bugfix state files; re-read state.json and the tail of this log to resume.\n' "$TIMESTAMP" >> "$notes_file"
done

exit 0
