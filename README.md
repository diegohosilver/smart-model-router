# smart-model-router

A Claude Code plugin that automatically routes every prompt to the most cost-efficient Anthropic model — **Haiku**, **Sonnet**, or **Opus** — based on task type, complexity, prompt length, and keyword signals.

## How it works

Every prompt passes through a **hybrid classifier** before Claude processes it:

```
      Prompt submitted
            │
            ▼
┌─────────────────────────────┐
│  Rule Pass 1: Opus keywords │  → opus   (investigate, analyze, audit, plan…)
└────────────┬────────────────┘
             │ no match
             ▼
┌─────────────────────────────┐
│  Rule Pass 2: Haiku keywords│  → haiku  (list, search, ls, cat, ≤60 chars)
└────────────┬────────────────┘
             │ no match
             ▼
┌─────────────────────────────┐
│  Rule Pass 3: Sonnet keywords│ → sonnet  (fix, debug, implement, refactor…)
└────────────┬────────────────┘
             │ still ambiguous
             ▼
┌─────────────────────────────┐
│  AI fallback (Haiku call)   │  → haiku / sonnet / opus
└────────────┬────────────────┘
             │ fallback
             ▼
         sonnet (default)
```

The classifier injects a `[ROUTE:MODEL]` tag via `additionalContext`. `CLAUDE.md` instructs Claude to delegate to a subagent of that tier, preserving the main session context.

## Routing tiers

| Tier | Model | Typical tasks |
|------|-------|--------------|
| 🟢 **Haiku** | `claude-haiku` | `ls`, `grep`, `cat`, "what is X", short lookups, file searches |
| 🟡 **Sonnet** | `claude-sonnet` | Fix bugs, write tests, edits, debugging, refactoring, implementation |
| 🔴 **Opus** | `claude-opus` | Investigation, root cause analysis, audits, design docs, planning |

## Installation

### Option A — Claude Code plugin marketplace (recommended)

Launch claude, add the marketplace and install the plugin:

```bash
/plugin marketplace add diegohosilver/smart-model-router
/plugin install smart-model-router
```

### Option B — install.sh script

```bash
git clone https://github.com/diegohosilver/smart-model-router
cd smart-model-router

# Install to default ~/.claude profile
bash install.sh

# Or to a custom profile
bash install.sh --profile ~/.claude-personal
```

Restart Claude Code (or start a new session) to activate the hook.

## Check routing status

```
/smart-model-router:model-status
```

## Manual override

Say "use haiku/sonnet/opus" in your prompt to override routing for that turn.

## Testing the classifier directly

```bash
echo '{"prompt": "list the files in src/"}' | bash plugin/hooks/classify.sh
# → {"additionalContext": "[ROUTE:HAIKU] (classifier: keyword:lookup/search)"}

echo '{"prompt": "fix the null pointer in user.service.ts"}' | bash plugin/hooks/classify.sh
# → {"additionalContext": "[ROUTE:SONNET] (classifier: keyword:coding/implementation)"}

echo '{"prompt": "investigate why the auth service is leaking memory"}' | bash plugin/hooks/classify.sh
# → {"additionalContext": "[ROUTE:OPUS] (classifier: keyword:investigation/analysis/planning)"}
```

## Uninstall

```bash
bash uninstall.sh

# Or for a custom profile
bash uninstall.sh --profile ~/.claude-personal
```

## Estimated savings

| Mix | Without router | With router | Savings |
|-----|---------------|-------------|---------|
| 50% lookup, 40% coding, 10% analysis | 100% Sonnet price | ~50% Haiku + 40% Sonnet + 10% Opus | ~55% |
| 30% lookup, 60% coding, 10% analysis | 100% Opus price | ~30% Haiku + 60% Sonnet + 10% Opus | ~75% |
