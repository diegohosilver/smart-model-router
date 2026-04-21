#!/usr/bin/env bash
# smart-model-router/hooks/classify.sh
#
# Classifies a user prompt and outputs a routing decision via JSON.
# Runs on UserPromptSubmit. Uses a hybrid approach:
#   1. Fast rule-based pass (keywords, length, patterns)
#   2. If ambiguous, falls back to a cheap Haiku subprocess call
#
# Output format (JSON on stdout, consumed by Claude Code):
#   { "additionalContext": "..." }
#
# The additionalContext injects a [ROUTE:MODEL] tag that CLAUDE.md
# instructs Claude to honour.
#
# Model tiers:
#   haiku  → trivial lookups, file searches, short explanations
#   sonnet → coding, debugging, implementation, refactoring (default)
#   opus   → investigation, analysis, planning ONLY

set -euo pipefail

# ── Read hook input ─────────────────────────────────────────────────────────
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('prompt') or data.get('user_prompt') or data.get('message') or '')
" 2>/dev/null || echo "")

if [[ -z "$PROMPT" ]]; then
  echo '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ""}}'
  exit 0
fi

PROMPT_LEN=${#PROMPT}
TIER=""
REASON=""

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ── RULE PASS 1: Opus — investigation / analysis / planning ONLY ──────────────
# Opus is reserved for tasks that are primarily about understanding, reasoning,
# or planning — NOT for implementation tasks, even large ones.
if echo "$PROMPT_LOWER" | grep -qE \
  'investigat|analyz|analys|diagnos|audit|root cause|post.?mortem|why (is|are|does|do|did|has|have)|how does .{20,}work|trace (through|the)|walk (me )?through (how|why|the)|understand (the|this|how|why)|figure out (why|what|how)|what (is|are) (causing|happening|going on)|review (and|then) (suggest|recommend|propose|plan)|plan (the|a|an|this)|planning|design (doc|document|proposal|spec|rfc)|write (a|an) (design doc|spec|rfc|proposal|plan|analysis|report)|strategic|tradeoff|compare (options|approaches|tradeoffs|alternatives)|pros and cons|should (we|i) (use|choose|adopt|migrate|switch)|recommend (an?|the) (approach|solution|architecture|strategy)'; then
  TIER="opus"
  REASON="keyword:investigation/analysis/planning"
fi

# ── RULE PASS 2: Haiku — pure lookup / search / trivial explain ──────────────
if [[ -z "$TIER" ]]; then
  if echo "$PROMPT_LOWER" | grep -qE \
    '^(what is|what are|list|show|find|search|grep|look up|where is|which file|how many|count|ls |cat |pwd|cd |echo |print |display |tell me what|define |meaning of)'; then
    TIER="haiku"
    REASON="keyword:lookup/search"
  fi
fi

# Haiku: search/find/grep anywhere in prompt (no implementation keywords)
if [[ -z "$TIER" ]]; then
  if echo "$PROMPT_LOWER" | grep -qE '(search|find|grep|look for|look up|locate|where is|which file|list all|show all)'; then
    if ! echo "$PROMPT_LOWER" | grep -qE 'fix |debug|implement|build|create|write|refactor|test|deploy|migrate|add (a|an) |update |analyz|plan|review|investigat|and (fix|update|change|modify|edit|refactor)'; then
      TIER="haiku"
      REASON="keyword:search/find"
    fi
  fi
fi

# Haiku: very short prompts (≤60 chars) with no coding or analysis keywords
if [[ -z "$TIER" && $PROMPT_LEN -le 60 ]]; then
  if ! echo "$PROMPT_LOWER" | grep -qE 'fix |debug|implement|build|create|write|refactor|test|deploy|migrate|add (a|an) |update |analyz|plan|review|investigat'; then
    TIER="haiku"
    REASON="short-prompt"
  fi
fi

# Haiku: short read/explain tasks (≤120 chars)
if [[ -z "$TIER" && $PROMPT_LEN -le 120 ]]; then
  if echo "$PROMPT_LOWER" | grep -qE '^(explain|summarize|describe|read|open|view|check|verify|confirm|is |are |does |do |can |will )'; then
    TIER="haiku"
    REASON="keyword:explain/read"
  fi
fi

# ── RULE PASS 3: Sonnet — coding tasks (single-file OR multi-file) ────────────
# Everything implementation-related goes to Sonnet, not Opus.
if [[ -z "$TIER" ]]; then
  if echo "$PROMPT_LOWER" | grep -qE \
    'fix |debug|implement|build|create|write (a |an )?(function|test|class|component|script|module)|add (a |an )?(function|method|class|test|endpoint|route|feature)|update (the |this )?(function|method|class|component)|refactor|migrate|deploy|edit|modify|change|rename|delete|remove (the|this)|make (this|the) (test|function|method)|resolve (the|this) (error|issue|bug|exception)|across (all|multiple|every)|entire (codebase|project|repo)|end.to.end'; then
    TIER="sonnet"
    REASON="keyword:coding/implementation"
  fi
fi

# ── AI FALLBACK: ambiguous prompts ───────────────────────────────────────────
# Uses `claude -p` (headless mode) — authenticates via your existing
# subscription session, no ANTHROPIC_API_KEY required.
if [[ -z "$TIER" ]]; then
  CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "")

  if [[ -n "$CLAUDE_BIN" ]]; then
    SNIPPET="${PROMPT:0:400}"
    CLASSIFY_PROMPT="Classify this task with exactly one word — haiku, sonnet, or opus — and nothing else.

haiku  = trivial lookups, file searches, grep/ls/cat, short one-liner explanations
sonnet = ALL implementation tasks: coding, debugging, writing tests, refactoring, migrations (even large ones)
opus   = investigation, analysis, planning, and design work ONLY — understanding why something is broken, auditing, writing specs/RFCs, comparing approaches, strategic decisions

Task: ${SNIPPET}"

    AI_TIER=$("$CLAUDE_BIN" -p "$CLASSIFY_PROMPT" \
      --model haiku \
      --output-format text \
      2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]' | head -c 10 || echo "")

    case "$AI_TIER" in
      haiku|sonnet|opus)
        TIER="$AI_TIER"
        REASON="ai-classifier(subscription)"
        ;;
      *)
        TIER="sonnet"
        REASON="ai-fallback-invalid"
        ;;
    esac
  else
    TIER="sonnet"
    REASON="default"
  fi
fi

# ── Resolve model ID from tier ────────────────────────────────────────────────
case "$TIER" in
  haiku)  MODEL="haiku" ;;
  opus)   MODEL="opus" ;;
  *)      MODEL="sonnet" ;;
esac

# ── Emit routing tag as additionalContext ─────────────────────────────────────
python3 -c "
import json
model = '$MODEL'
reason = '$REASON'
tag = f'[ROUTE:{model.upper()}] (classifier: {reason})'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': tag}}))
"
