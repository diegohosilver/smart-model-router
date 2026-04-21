# Smart Model Router — Routing Protocol

A `UserPromptSubmit` hook classifies every prompt and injects a `[ROUTE:*]` tag into your context via `additionalContext`. You **must** honour these tags by delegating to the appropriate model tier.

## Routing table

| Tag injected | Action |
|--------------|--------|
| `[ROUTE:HAIKU]` | Delegate the entire task to `Agent(model="haiku")`. Present the result cleanly to the user — do not dump raw agent output. |
| `[ROUTE:SONNET]` | Answer directly (you are Sonnet by default). Spawn `Agent(model="haiku")` only for background file searches. |
| `[ROUTE:OPUS]` | Spawn `Agent(model="opus")` for the full response. Present the result cleanly to the user — do not dump raw agent output. |

## When each model is used

- **Haiku** — lookups, file searches, `ls`/`cat`/`grep`, short factual questions
- **Sonnet** — ALL implementation work: coding, debugging, writing tests, refactoring, migrations, edits (even large multi-file ones)
- **Opus** — investigation, analysis, and planning ONLY: root cause analysis, audits, writing specs/RFCs/design docs, comparing approaches, diagnosing why something is broken, strategic decisions

## Rules

1. If the injected tag says HAIKU: do not reason yourself — immediately delegate with `Agent(model="haiku", prompt=<original_user_prompt>)` and present the result cleanly to the user (formatted markdown, no raw agent metadata).
2. If the injected tag says OPUS: spawn `Agent(model="opus", prompt=<original_user_prompt>)` and present the result cleanly to the user (formatted markdown, no raw agent metadata).
3. If the injected tag says SONNET (or is absent): respond directly as normal.
4. Never mention the `[ROUTE:*]` tag to the user unless they ask about routing.
5. If the user explicitly says "use haiku/sonnet/opus" in their prompt, that overrides the tag.
6. **Opus is never used for implementation tasks**, even very large ones — those go to Sonnet.
