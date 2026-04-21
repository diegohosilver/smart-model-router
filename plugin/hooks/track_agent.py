#!/usr/bin/env python3
"""
PostToolUse hook: records token usage from Agent subagent calls.

Reads hook JSON from stdin. When the Agent tool completes, extracts the
model tier and structured usage from tool_response, then appends a record to
~/.cache/smart-model-router/agents_{session_id}.jsonl so session_summary.py
can include subagent usage in the cost report.
"""
import json
import sys
from pathlib import Path


def model_tier(model_id: str) -> str:
    m = (model_id or "").lower()
    if "haiku" in m:
        return "haiku"
    if "opus" in m:
        return "opus"
    return "sonnet"


def main():
    raw = sys.stdin.read()
    try:
        hook = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    if hook.get("tool_name") != "Agent":
        sys.exit(0)

    session_id = hook.get("session_id", "")
    if not session_id:
        sys.exit(0)

    tool_input    = hook.get("tool_input", {}) or {}
    tool_response = hook.get("tool_response", {}) or {}
    usage         = tool_response.get("usage", {}) or {}

    if not usage:
        sys.exit(0)

    tier = model_tier(str(tool_input.get("model", "") or ""))

    record = {
        "model":       tier,
        "input":       usage.get("input_tokens", 0),
        "output":      usage.get("output_tokens", 0),
        "cache_write": usage.get("cache_creation_input_tokens", 0),
        "cache_read":  usage.get("cache_read_input_tokens", 0),
    }

    if record["input"] + record["output"] + record["cache_write"] + record["cache_read"] == 0:
        sys.exit(0)

    cache_dir = Path.home() / ".cache" / "smart-model-router"
    cache_dir.mkdir(parents=True, exist_ok=True)

    with open(cache_dir / f"agents_{session_id}.jsonl", "a") as f:
        f.write(json.dumps(record) + "\n")


if __name__ == "__main__":
    main()
