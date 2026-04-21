#!/usr/bin/env python3
"""
smart-model-router/hooks/session_summary.py

Usage:
  As a command:  python3 session_summary.py [transcript_path]
                 If no path is given, auto-discovers the most recent session
                 transcript from known Claude profile directories.
  As a hook:     echo '<json>' | python3 session_summary.py
                 Reads transcript_path from hook JSON on stdin; exits silently
                 (no output) — display is handled by the model-status skill.
"""

import json
import os
import sys
from collections import defaultdict
from pathlib import Path

# ── Model pricing (per million tokens, as of April 2026) ─────────────────────
PRICING = {
    "haiku":  (0.80,   4.00,  1.00,  0.08),
    "sonnet": (3.00,  15.00,  3.75,  0.30),
    "opus":   (15.00, 75.00, 18.75,  1.50),
}



def model_tier(model_id: str) -> str:
    m = (model_id or "").lower()
    if "haiku"  in m: return "haiku"
    if "opus"   in m: return "opus"
    if "sonnet" in m: return "sonnet"
    return "sonnet"

def fmt_tokens(n: int) -> str:
    if n >= 1_000_000: return f"{n/1_000_000:.2f}M"
    if n >= 1_000:     return f"{n/1_000:.1f}K"
    return str(n)

def fmt_cost(usd: float) -> str:
    if usd < 0.001: return "<$0.001"
    if usd < 0.01:  return f"${usd:.4f}"
    return f"${usd:.3f}"

def est_cost(tier, usage):
    if tier not in PRICING:
        return 0.0
    ip, op, cw, cr = PRICING[tier]
    return (
        usage["input"]        / 1_000_000 * ip +
        usage["output"]       / 1_000_000 * op +
        usage["cache_write"]  / 1_000_000 * cw +
        usage["cache_read"]   / 1_000_000 * cr
    )

def find_latest_transcript() -> str:
    """Return the most recently modified session JSONL across known profile dirs."""
    home = Path.home()
    search_roots = [
        home / ".claude" / "projects",
        home / ".claude-dexterity" / "projects",
        home / ".claude-personal" / "projects",
    ]
    best = None
    best_mtime = 0.0
    for root in search_roots:
        if not root.exists():
            continue
        for f in root.rglob("*.jsonl"):
            try:
                mt = f.stat().st_mtime
                if mt > best_mtime:
                    best_mtime = mt
                    best = str(f)
            except OSError:
                pass
    return best or ""

def parse_usage(transcript_path: str) -> dict:
    usage = defaultdict(lambda: defaultdict(int))
    with open(transcript_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("type") != "assistant":
                continue
            msg   = obj.get("message", {})
            model = msg.get("model", "") or obj.get("model", "")
            u     = msg.get("usage", {})
            if not u:
                continue
            tier = model_tier(model)
            usage[tier]["input"]       += u.get("input_tokens", 0)
            usage[tier]["output"]      += u.get("output_tokens", 0)
            usage[tier]["cache_write"] += u.get("cache_creation_input_tokens", 0)
            usage[tier]["cache_read"]  += u.get("cache_read_input_tokens", 0)
            usage[tier]["turns"]       += 1
    return usage

def parse_agent_usage(session_id: str) -> dict:
    """Read per-session agent sidecar; return {tier: {input, output, cache_write, cache_read, turns}}."""
    sidecar = Path.home() / ".cache" / "smart-model-router" / f"agents_{session_id}.jsonl"
    usage = defaultdict(lambda: defaultdict(int))
    if not sidecar.exists():
        return usage
    with open(sidecar) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            tier = model_tier(rec.get("model", ""))
            usage[tier]["input"]       += rec.get("input", 0)
            usage[tier]["output"]      += rec.get("output", 0)
            usage[tier]["cache_write"] += rec.get("cache_write", 0)
            usage[tier]["cache_read"]  += rec.get("cache_read", 0)
            usage[tier]["turns"]       += 1
    return usage

def build_summary(main_usage: dict, agent_usage: dict) -> str:
    TIER_ORDER  = ["haiku", "sonnet", "opus"]
    TIER_LABELS = {"haiku": "Haiku", "sonnet": "Sonnet", "opus": "Opus"}

    all_tiers = set(main_usage) | set(agent_usage)

    W = [14, 10, 10, 12]
    sep   = "-" * (sum(W) + 6)
    thick = "=" * (sum(W) + 6)

    rows = [thick, " Token Usage — Smart Model Router", thick]
    rows.append(
        f"  {'Model':<{W[0]}}"
        f"{'Input':>{W[1]}}"
        f"{'Output':>{W[2]}}"
        f"{'Est. Cost':>{W[3]}}"
    )
    rows.append(sep)

    total_input = total_output = 0
    total_cost  = 0.0
    total_main_turns = total_agent_turns = 0

    for tier in TIER_ORDER:
        if tier not in all_tiers:
            continue

        mu = main_usage.get(tier, defaultdict(int))
        au = agent_usage.get(tier, defaultdict(int))

        inp  = mu["input"] + mu["cache_write"] + mu["cache_read"] + au["input"]
        out  = mu["output"] + au["output"]
        cost = est_cost(tier, mu) + est_cost(tier, au)
        main_turns  = mu["turns"]
        agent_turns = au["turns"]

        total_input       += inp
        total_output      += out
        total_cost        += cost
        total_main_turns  += main_turns
        total_agent_turns += agent_turns

        label = TIER_LABELS.get(tier, tier)

        parts = []
        if main_turns:
            parts.append(f"{main_turns} turn{'s' if main_turns != 1 else ''}")
        if agent_turns:
            parts.append(f"{agent_turns} subagent call{'s' if agent_turns != 1 else ''}")
        turn_str = ", ".join(parts) if parts else "0 turns"

        rows.append(
            f"  {label:<{W[0]}}"
            f"{fmt_tokens(inp):>{W[1]}}"
            f"{fmt_tokens(out):>{W[2]}}"
            f"{fmt_cost(cost):>{W[3]}}"
            f"  ({turn_str})"
        )

    rows.append(sep)
    total_turns = total_main_turns + total_agent_turns
    rows.append(
        f"  {'TOTAL':<{W[0]}}"
        f"{fmt_tokens(total_input):>{W[1]}}"
        f"{fmt_tokens(total_output):>{W[2]}}"
        f"{fmt_cost(total_cost):>{W[3]}}"
        f"  ({total_turns} turn{'s' if total_turns != 1 else ''})"
    )
    rows.append(thick)

    routed_tiers = [t for t in TIER_ORDER if t in all_tiers]
    if len(routed_tiers) > 1:
        parts = []
        for t in routed_tiers:
            mu = main_usage.get(t, defaultdict(int))
            au = agent_usage.get(t, defaultdict(int))
            n  = mu["turns"] + au["turns"]
            if n:
                parts.append(f"{n} {TIER_LABELS[t]}")
        if parts:
            rows.append(f"  Routed: {', '.join(parts)}")
            rows.append(thick)

    return "\n".join(rows)

def main():
    # ── Command mode: path passed as CLI arg ──────────────────────────────────
    if len(sys.argv) > 1 and sys.argv[1] != "--cli":
        transcript_path = sys.argv[1]
    # ── Command mode: no args or --cli flag → auto-discover ───────────────────
    elif sys.stdin.isatty() or "--cli" in sys.argv:
        transcript_path = find_latest_transcript()
    # ── Hook mode: read JSON from stdin ───────────────────────────────────────
    else:
        raw = sys.stdin.read()
        try:
            hook_input = json.loads(raw)
        except json.JSONDecodeError:
            sys.exit(0)
        # Hook mode: no display — skill handles output
        sys.exit(0)

    if not transcript_path or not Path(transcript_path).exists():
        print("No session transcript found.", file=sys.stderr)
        sys.exit(1)

    session_id  = Path(transcript_path).stem
    main_usage  = parse_usage(transcript_path)
    agent_usage = parse_agent_usage(session_id)

    if not main_usage and not agent_usage:
        print("No token usage recorded yet.", file=sys.stderr)
        sys.exit(0)

    print(build_summary(main_usage, agent_usage))

if __name__ == "__main__":
    main()
