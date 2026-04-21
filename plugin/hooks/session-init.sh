#!/usr/bin/env bash
# smart-model-router/hooks/session-init.sh
#
# SessionStart hook — injects routing protocol into context on every session.
# Mirrors how caveman injects its rules: no CLAUDE.md write required.
# Works when installed via marketplace (no install.sh CLAUDE.md injection).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_MD="$SCRIPT_DIR/../CLAUDE.md"

if [[ ! -f "$CLAUDE_MD" ]]; then
  exit 0
fi

CONTENT=$(cat "$CLAUDE_MD")

python3 -c "
import json, sys
content = sys.stdin.read().strip()
if content:
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': content}}))
" <<< "$CONTENT"
