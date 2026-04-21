#!/usr/bin/env bash
# smart-model-router/install.sh
#
# Idempotent installer. Safe to run multiple times.
#
# Usage:
#   bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse args ────────────────────────────────────────────────────────────────
PROFILE_DIR="$HOME/.claude"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p)
      PROFILE_DIR="${2:-}"
      [[ -z "$PROFILE_DIR" ]] && { echo "Error: --profile requires a path"; exit 1; }
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash install.sh [--profile <path>]"
      exit 1
      ;;
  esac
done

PROFILE_DIR="${PROFILE_DIR%/}"  # strip trailing slash
PLUGINS_DIR="$PROFILE_DIR/plugins/smart-model-router"
SETTINGS_FILE="$PROFILE_DIR/settings.json"
CLAUDE_MD_FILE="$PROFILE_DIR/CLAUDE.md"

echo "Installing smart-model-router to profile: $PROFILE_DIR"
echo ""

# ── Step 1: Copy plugin files ─────────────────────────────────────────────────
echo "[1/4] Copying plugin files → $PLUGINS_DIR"

mkdir -p "$PLUGINS_DIR/hooks" "$PLUGINS_DIR/skills/model-status" "$PLUGINS_DIR/.claude-plugin"

cp "$SCRIPT_DIR/plugin/hooks/classify.sh"          "$PLUGINS_DIR/hooks/classify.sh"
cp "$SCRIPT_DIR/plugin/hooks/session_summary.py"   "$PLUGINS_DIR/hooks/session_summary.py"
cp "$SCRIPT_DIR/plugin/hooks/track_agent.py"       "$PLUGINS_DIR/hooks/track_agent.py"
cp "$SCRIPT_DIR/plugin/hooks/hooks.json"           "$PLUGINS_DIR/hooks/hooks.json"
cp "$SCRIPT_DIR/plugin/.claude-plugin/plugin.json" "$PLUGINS_DIR/.claude-plugin/plugin.json"
cp "$SCRIPT_DIR/plugin/CLAUDE.md"                  "$PLUGINS_DIR/CLAUDE.md"
cp "$SCRIPT_DIR/plugin/skills/model-status/SKILL.md" "$PLUGINS_DIR/skills/model-status/SKILL.md"

chmod +x "$PLUGINS_DIR/hooks/classify.sh"
echo "    Done."

# ── Step 2: Register plugin in installed_plugins.json + enabledPlugins ────────
echo "[2/4] Registering plugin for skill discovery"

INSTALLED_PLUGINS_FILE="$PROFILE_DIR/plugins/installed_plugins.json"
PLUGINS_DIR="$PLUGINS_DIR" INSTALLED_PLUGINS_FILE="$INSTALLED_PLUGINS_FILE" python3 - <<PYEOF
import json, os, sys
from datetime import datetime, timezone

install_path    = os.environ["PLUGINS_DIR"]
registry_file   = os.environ["INSTALLED_PLUGINS_FILE"]
plugin_key      = "smart-model-router@local"

if os.path.exists(registry_file):
    with open(registry_file) as f:
        registry = json.load(f)
else:
    registry = {"version": 2, "plugins": {}}

existing = registry.get("plugins", {}).get(plugin_key, [])
if existing and any(e.get("installPath") == install_path for e in existing):
    print("    Already registered in installed_plugins.json — skipping.")
else:
    registry.setdefault("plugins", {})[plugin_key] = [{
        "scope": "user",
        "installPath": install_path,
        "version": "1.0.4",
        "installedAt": datetime.now(timezone.utc).isoformat(),
        "lastUpdated": datetime.now(timezone.utc).isoformat()
    }]
    with open(registry_file, "w") as f:
        json.dump(registry, f, indent=2)
        f.write("\n")
    print("    Registered in installed_plugins.json.")
PYEOF

# Add to enabledPlugins in settings.json
SETTINGS_FILE="$SETTINGS_FILE" python3 - <<PYEOF
import json, os, sys

settings_file = os.environ["SETTINGS_FILE"]
plugin_key    = "smart-model-router@local"

if os.path.exists(settings_file):
    with open(settings_file) as f:
        settings = json.load(f)
else:
    settings = {}

enabled = settings.setdefault("enabledPlugins", {})
if plugin_key in enabled:
    print("    Already in enabledPlugins — skipping.")
    sys.exit(0)

enabled[plugin_key] = True
with open(settings_file, "w") as f:
    json.dump(settings, f, indent=4)
    f.write("\n")
print("    Added to enabledPlugins.")
PYEOF

# ── Step 3: Register UserPromptSubmit hook in settings.json ───────────────────
echo "[3/4] Registering hook in $SETTINGS_FILE"

HOOK_COMMAND="bash \"$SCRIPT_DIR/plugin/hooks/classify.sh\""

SETTINGS_FILE="$SETTINGS_FILE" HOOK_COMMAND="$HOOK_COMMAND" python3 - <<PYEOF
import json, os, sys

settings_file = os.environ["SETTINGS_FILE"]
hook_command  = os.environ["HOOK_COMMAND"]

# Load or init
if os.path.exists(settings_file):
    with open(settings_file) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})
ups   = hooks.setdefault("UserPromptSubmit", [])

# Check if already registered (exact command match)
already = any(
    h.get("type") == "command" and h.get("command") == hook_command
    for entry in ups
    for h in entry.get("hooks", [])
)

if already:
    print("    Already registered — skipping.")
    sys.exit(0)

ups.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": hook_command}]
})

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=4)
    f.write("\n")

print("    Registered.")
PYEOF

# ── Step 4: Inject routing instructions into CLAUDE.md ───────────────────────
echo "[4/4] Injecting routing instructions into $CLAUDE_MD_FILE"

MARKER="# Smart Model Router — Routing Protocol"

if [[ -f "$CLAUDE_MD_FILE" ]] && grep -qF "$MARKER" "$CLAUDE_MD_FILE"; then
    SCRIPT_DIR="$SCRIPT_DIR" CLAUDE_MD_FILE="$CLAUDE_MD_FILE" python3 - <<PYEOF
import os
path     = os.environ["CLAUDE_MD_FILE"]
new_block = open(os.environ["SCRIPT_DIR"] + "/plugin/CLAUDE.md").read().strip()
marker   = "# Smart Model Router — Routing Protocol"

with open(path) as f:
    content = f.read()

idx = content.find(marker)
before = content[:idx].rstrip("\n")

with open(path, "w") as f:
    f.write(before + "\n" + new_block + "\n")
print("    Updated existing section.")
PYEOF
else
    echo "" >> "$CLAUDE_MD_FILE"
    cat "$SCRIPT_DIR/plugin/CLAUDE.md" >> "$CLAUDE_MD_FILE"
    echo "    Injected."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  • Restart Claude Code (or start a new session) to activate the hook."
echo "  • Run /smart-model-router:model-status to verify routing is working."
echo "  • To uninstall: bash \"$SCRIPT_DIR/uninstall.sh\" --profile \"$PROFILE_DIR\""
