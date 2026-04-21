#!/usr/bin/env node
'use strict';
// smart-model-router/hooks/classify.js
//
// Classifies a user prompt and outputs a routing decision via JSON.
// Runs on UserPromptSubmit. Hybrid approach:
//   1. Fast rule-based pass (keywords, length, patterns)
//   2. If ambiguous, falls back to a cheap Haiku subprocess call
//
// Output: { "hookSpecificOutput": { "hookEventName": "UserPromptSubmit", "additionalContext": "[ROUTE:MODEL] ..." } }

const { spawnSync } = require('child_process');

const chunks = [];
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => chunks.push(d));
process.stdin.on('end', () => run(chunks.join('')));

function classify(lower, len) {
  // PASS 1: Opus — investigation / analysis / planning ONLY
  if (/investigat|analyz|analys|diagnos|audit|root cause|post.?mortem|why (is|are|does|do|did|has|have)|how does .{20,}work|trace (through|the)|walk (me )?through (how|why|the)|understand (the|this|how|why)|figure out (why|what|how)|what (is|are) (causing|happening|going on)|review (and|then) (suggest|recommend|propose|plan)|plan (the|a|an|this)\b|planning|design (doc|document|proposal|spec|rfc)|write (a|an) (design doc|spec|rfc|proposal|plan|analysis|report)|strategic|tradeoff|compare (options|approaches|tradeoffs|alternatives)|pros and cons|should (we|i) (use|choose|adopt|migrate|switch)|recommend (an?|the) (approach|solution|architecture|strategy)/.test(lower)) {
    return ['opus', 'keyword:investigation/analysis/planning'];
  }

  // PASS 2: Haiku — pure lookup / search / trivial explain
  if (/^(what is|what are|list|show|find|search|grep|look up|where is|which file|how many|count|ls |cat |pwd|cd |echo |print |display |tell me what|define |meaning of)/.test(lower)) {
    return ['haiku', 'keyword:lookup/search'];
  }

  // Haiku: search/find anywhere (no implementation keywords)
  if (/(search|find|grep|look for|look up|locate|where is|which file|list all|show all)/.test(lower)) {
    if (!/fix |debug|implement|build|create|write|refactor|test|deploy|migrate|add (a|an) |update |analyz|plan|review|investigat|and (fix|update|change|modify|edit|refactor)/.test(lower)) {
      return ['haiku', 'keyword:search/find'];
    }
  }

  // Haiku: very short prompts (≤60 chars), no coding keywords
  if (len <= 60 && !/fix |debug|implement|build|create|write|refactor|test|deploy|migrate|add (a|an) |update |analyz|plan|review|investigat/.test(lower)) {
    return ['haiku', 'short-prompt'];
  }

  // Haiku: short read/explain tasks (≤120 chars)
  if (len <= 120 && /^(explain|summarize|describe|read|open|view|check|verify|confirm|is |are |does |do |can |will )/.test(lower)) {
    return ['haiku', 'keyword:explain/read'];
  }

  // PASS 3: Sonnet — coding / implementation
  if (/fix |debug|implement|build|create|write (a |an )?(function|test|class|component|script|module)|add (a |an )?(function|method|class|test|endpoint|route|feature)|update (the |this )?(function|method|class|component)|refactor|migrate|deploy|edit|modify|change|rename|delete|remove (the|this)|make (this|the) (test|function|method)|resolve (the|this) (error|issue|bug|exception)|across (all|multiple|every)|entire (codebase|project|repo)|end.to.end/.test(lower)) {
    return ['sonnet', 'keyword:coding/implementation'];
  }

  return null; // needs AI fallback
}

function run(raw) {
  let prompt = '';
  try {
    const data = JSON.parse(raw);
    prompt = data.prompt || data.user_prompt || data.message || '';
  } catch (e) {}

  const empty = () => process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: '' }
  }));

  if (!prompt) return empty();

  const lower = prompt.toLowerCase();
  const len = prompt.length;

  let tier, reason;
  const quick = classify(lower, len);

  if (quick) {
    [tier, reason] = quick;
  } else {
    // AI fallback via claude -p (uses subscription session, no API key needed)
    const snippet = prompt.slice(0, 400);
    const classifyPrompt =
      'Classify this task with exactly one word — haiku, sonnet, or opus — and nothing else.\n\n' +
      'haiku  = trivial lookups, file searches, grep/ls/cat, short one-liner explanations\n' +
      'sonnet = ALL implementation tasks: coding, debugging, writing tests, refactoring, migrations (even large ones)\n' +
      'opus   = investigation, analysis, planning, and design work ONLY — understanding why something is broken, auditing, writing specs/RFCs, comparing approaches, strategic decisions\n\n' +
      'Task: ' + snippet;

    try {
      const res = spawnSync('claude', ['-p', classifyPrompt, '--model', 'haiku', '--output-format', 'text'], {
        timeout: 10000,
        encoding: 'utf8',
        windowsHide: true
      });
      if (res.status === 0 && res.stdout) {
        const ai = res.stdout.toLowerCase().replace(/\s/g, '').slice(0, 10);
        if (['haiku', 'sonnet', 'opus'].includes(ai)) {
          tier = ai;
          reason = 'ai-classifier(subscription)';
        } else {
          tier = 'sonnet';
          reason = 'ai-fallback-invalid';
        }
      } else {
        tier = 'sonnet';
        reason = 'default';
      }
    } catch (e) {
      tier = 'sonnet';
      reason = 'default';
    }
  }

  const model = tier === 'haiku' ? 'haiku' : tier === 'opus' ? 'opus' : 'sonnet';
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: `[ROUTE:${model.toUpperCase()}] (classifier: ${reason})`
    }
  }));
}
