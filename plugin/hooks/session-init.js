#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const claudeMd = path.join(__dirname, '..', 'CLAUDE.md');
if (fs.existsSync(claudeMd)) {
  process.stdout.write(fs.readFileSync(claudeMd, 'utf8'));
}
