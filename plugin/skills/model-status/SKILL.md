---
description: Show token usage and cost breakdown for the current session, and explain how the smart-model-router plugin classifies prompts. Use when the user asks about model routing, token usage, session cost, or which model is active.
disable-model-invocation: false
---

# Smart Model Router — Status & Token Usage

Run the following command and display its output verbatim:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/session_summary.py" --cli
```

Then report the current active model and explain how routing works:

## Routing tiers

| Tag | Model | When used |
|-----|-------|-----------|
| `[ROUTE:HAIKU]` | claude-haiku | Lookups, searches, `ls`/`cat`/`grep`, short explanations |
| `[ROUTE:SONNET]` | claude-sonnet | Coding, debugging, writing tests, refactoring, edits |
| `[ROUTE:OPUS]` | claude-opus | Investigation, analysis, planning, design docs, audits |

## How it works

Every prompt passes through a **hybrid classifier** (`hooks/classify.sh`) on `UserPromptSubmit`:

1. **Rule pass 1** — Opus keywords: investigate, analyze, diagnose, audit, plan, design doc, etc.
2. **Rule pass 2** — Haiku keywords: lookup, search, list, short prompts ≤60 chars
3. **Rule pass 3** — Sonnet keywords: fix, debug, implement, refactor, edit, etc.
4. **AI fallback** — ambiguous prompts go to a headless Haiku call for classification
5. **Default** — falls back to Sonnet

The classifier injects a `[ROUTE:MODEL]` tag via `additionalContext`. Claude delegates to a subagent of that tier, keeping the main session context intact.

## Manual override

- Say "use haiku/sonnet/opus" in your prompt to override for that turn
