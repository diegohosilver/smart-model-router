#!/usr/bin/env node
'use strict';
// PostToolUse hook: records token usage from Agent subagent calls.

const fs = require('fs');
const path = require('path');
const os = require('os');

function modelTier(modelId) {
  const m = (modelId || '').toLowerCase();
  if (m.includes('haiku')) return 'haiku';
  if (m.includes('opus')) return 'opus';
  return 'sonnet';
}

const chunks = [];
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => chunks.push(d));
process.stdin.on('end', () => {
  let hook;
  try { hook = JSON.parse(chunks.join('')); } catch (e) { process.exit(0); }

  if (hook.tool_name !== 'Agent') process.exit(0);

  const sessionId = hook.session_id || '';
  if (!sessionId) process.exit(0);

  const toolInput = hook.tool_input || {};
  const usage = (hook.tool_response || {}).usage || {};
  if (!usage) process.exit(0);

  const record = {
    model:       modelTier(String(toolInput.model || '')),
    input:       usage.input_tokens || 0,
    output:      usage.output_tokens || 0,
    cache_write: usage.cache_creation_input_tokens || 0,
    cache_read:  usage.cache_read_input_tokens || 0,
  };

  if (record.input + record.output + record.cache_write + record.cache_read === 0) process.exit(0);

  const cacheDir = path.join(os.homedir(), '.cache', 'smart-model-router');
  fs.mkdirSync(cacheDir, { recursive: true });
  fs.appendFileSync(path.join(cacheDir, `agents_${sessionId}.jsonl`), JSON.stringify(record) + '\n', 'utf8');
});
