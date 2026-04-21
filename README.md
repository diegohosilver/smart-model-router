# smart-model-router

A Claude Code plugin that automatically routes every prompt to the most cost-efficient Anthropic model — **Haiku**, **Sonnet**, or **Opus** — based on task type, complexity, prompt length, and keyword signals.

## How it works

Every prompt passes through a **hybrid classifier** before Claude processes it:

```
Prompt submitted
      │
      ▼
┌─────────────────────────────┐
│  Rule Pass 1: hard keywords │  → haiku  (lookup/search/list)
│                             │  → opus   (architecture/security)
└────────────┬────────────────┘
             │ ambiguous
             ▼
┌─────────────────────────────┐
│  Rule Pass 2: code signals  │  → sonnet  (single-file coding)
│  + prompt length            │  → opus    (≥800 chars)
│                             │  → haiku   (≤60 chars, non-code)
└────────────┬────────────────┘
             │ still ambiguous
             ▼
┌─────────────────────────────┐
│  AI fallback (Haiku call)   │  → haiku / sonnet / opus
│  (requires ANTHROPIC_API_KEY│
└────────────┬────────────────┘
             │ no API key
             ▼
         sonnet (default)
```

The classifier injects a `[ROUTE:MODEL]` tag via `additionalContext`. `CLAUDE.md` instructs Claude to delegate to a subagent of that tier, preserving the main session context.

## Routing tiers

| Tier | Model | Typical tasks |
|------|-------|--------------|
| 🟢 **Haiku** | `claude-haiku-4-5` | `ls`, `grep`, `cat`, "what is X", short lookups, file searches |
| 🟡 **Sonnet** | `claude-sonnet-4-6` | Fix bugs, write tests, single-file edits, debugging, moderate tasks |
| 🔴 **Opus** | `claude-opus-4-6` | Architecture, large refactors, security reviews, complex multi-step plans |

## Installation

### Option A — Project-level (one project)

```bash
# Copy plugin into your project
cp -r smart-model-router /your/project/.claude/plugins/

# Add to .claude/settings.json in your project
```

Then add to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/plugins/smart-model-router/hooks/classify.sh"
          }
        ]
      }
    ]
  }
}
```

### Option B — Global (all projects)

```bash
# Copy plugin globally
cp -r smart-model-router ~/.claude/plugins/

# Add to ~/.claude/settings.json
```

Then add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/plugins/smart-model-router/hooks/classify.sh"
          }
        ]
      }
    ]
  }
}
```

Also append the routing protocol to your global `~/.claude/CLAUDE.md` (or create it):

```bash
cat smart-model-router/CLAUDE.md >> ~/.claude/CLAUDE.md
```

### Option C — Test locally first (recommended)

```bash
claude --plugin-dir ./smart-model-router
```

## Optional: AI fallback classifier

When the rule-based pass is ambiguous, the classifier spawns `claude -p` as a headless subprocess — a single-turn Haiku call that uses your **existing subscription session** (Pro, Max, Team, or Enterprise). No `ANTHROPIC_API_KEY` needed.

This adds ~200–400ms latency on ambiguous prompts but improves routing accuracy for edge cases. It's completely automatic as long as the `claude` CLI is in your `PATH` (which it is if Claude Code is installed).

## Manual override

You can always override routing for a session:

```
/model haiku    — force Haiku
/model sonnet   — force Sonnet
/model opus     — force Opus
/model default  — restore default
```

Or inline in your prompt: "use opus to…" / "use haiku to…"

## Check routing status

```
/smart-model-router:model-status
```

## Testing the classifier directly

```bash
echo '{"prompt": "what files are in src/"}' | bash hooks/classify.sh
# → {"additionalContext": "[ROUTE:HAIKU] (classifier: keyword:lookup/search)"}

echo '{"prompt": "refactor the entire authentication system to use JWT"}' | bash hooks/classify.sh
# → {"additionalContext": "[ROUTE:OPUS] (classifier: keyword:architecture/deep-reasoning)"}

echo '{"prompt": "fix the null pointer in user.service.ts"}' | bash hooks/classify.sh
# → {"additionalContext": "[ROUTE:SONNET] (classifier: keyword:coding)"}
```

## Estimated savings

| Mix | Without router | With router | Savings |
|-----|---------------|-------------|---------|
| 50% lookup, 40% coding, 10% architecture | 100% Sonnet price | ~35% Sonnet + 50% Haiku + 15% Opus | ~55% |
| 30% lookup, 60% coding, 10% architecture | 100% Opus price | ~25% Haiku + 65% Sonnet + 10% Opus | ~75% |
