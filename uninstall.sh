#!/usr/bin/env bash
# smart-model-router/uninstall.sh
#
# Removes the plugin files, hook registration, and CLAUDE.md section.
#
# Usage:
#   bash uninstall.sh                          # uninstalls from ~/.claude
#   bash uninstall.sh --profile ~/.claude-dexterity
#   bash uninstall.sh -p ~/.claude-dexterity

set -euo pipefail

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
      echo "Usage: bash uninstall.sh [--profile <path>]"
      exit 1
      ;;
  esac
done

PROFILE_DIR="${PROFILE_DIR%/}"
PLUGINS_DIR="$PROFILE_DIR/plugins/smart-model-router"
SETTINGS_FILE="$PROFILE_DIR/settings.json"
CLAUDE_MD_FILE="$PROFILE_DIR/CLAUDE.md"

echo "Uninstalling smart-model-router from profile: $PROFILE_DIR"
echo ""

# ── Step 1: Remove plugin files ───────────────────────────────────────────────
echo "[1/4] Removing plugin files"
if [[ -d "$PLUGINS_DIR" ]]; then
    rm -rf "$PLUGINS_DIR"
    echo "    Removed $PLUGINS_DIR"
else
    echo "    Not found — skipping."
fi

# ── Step 2: Deregister plugin from installed_plugins.json + enabledPlugins ────
echo "[2/4] Deregistering plugin"

INSTALLED_PLUGINS_FILE="$PROFILE_DIR/plugins/installed_plugins.json"
if [[ ! -f "$INSTALLED_PLUGINS_FILE" ]]; then
    echo "    installed_plugins.json not found — skipping."
else
INSTALLED_PLUGINS_FILE="$INSTALLED_PLUGINS_FILE" python3 - <<PYEOF
import json, os

registry_file = os.environ["INSTALLED_PLUGINS_FILE"]
plugin_key    = "smart-model-router@local"

with open(registry_file) as f:
    registry = json.load(f)

if plugin_key in registry.get("plugins", {}):
    del registry["plugins"][plugin_key]
    with open(registry_file, "w") as f:
        json.dump(registry, f, indent=2)
        f.write("\n")
    print("    Removed from installed_plugins.json.")
else:
    print("    Not found in installed_plugins.json — skipping.")
PYEOF
fi

if [[ -f "$SETTINGS_FILE" ]]; then
SETTINGS_FILE="$SETTINGS_FILE" python3 - <<PYEOF
import json, os, sys

settings_file = os.environ["SETTINGS_FILE"]
plugin_key    = "smart-model-router@local"

with open(settings_file) as f:
    settings = json.load(f)

enabled = settings.get("enabledPlugins", {})
if plugin_key in enabled:
    del enabled[plugin_key]
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=4)
        f.write("\n")
    print("    Removed from enabledPlugins.")
else:
    print("    Not in enabledPlugins — skipping.")
PYEOF
fi

# ── Step 3: Remove hook from settings.json ────────────────────────────────────
echo "[3/4] Removing hook from $SETTINGS_FILE"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "    settings.json not found — skipping."
else
SETTINGS_FILE="$SETTINGS_FILE" python3 - <<PYEOF
import json, os, sys

settings_file = os.environ["SETTINGS_FILE"]

with open(settings_file) as f:
    settings = json.load(f)

ups = settings.get("hooks", {}).get("UserPromptSubmit", [])
original_len = len(ups)

# Remove entries whose command references classify.sh from smart-model-router
filtered = [
    entry for entry in ups
    if not any(
        "classify.sh" in h.get("command", "") and "smart-model-router" in h.get("command", "")
        for h in entry.get("hooks", [])
    )
]

if len(filtered) == original_len:
    print("    No matching hook found — skipping.")
    sys.exit(0)

if filtered:
    settings["hooks"]["UserPromptSubmit"] = filtered
else:
    del settings["hooks"]["UserPromptSubmit"]
    if not settings["hooks"]:
        del settings["hooks"]

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=4)
    f.write("\n")

print(f"    Removed {original_len - len(filtered)} hook entry(ies).")
PYEOF
fi

# ── Step 4: Remove routing section from CLAUDE.md ────────────────────────────
echo "[4/4] Removing routing instructions from $CLAUDE_MD_FILE"

START_MARKER="# Smart Model Router — Routing Protocol"

if [[ ! -f "$CLAUDE_MD_FILE" ]]; then
    echo "    CLAUDE.md not found — skipping."
elif ! grep -qF "$START_MARKER" "$CLAUDE_MD_FILE"; then
    echo "    Section not found — skipping."
else
    CLAUDE_MD_FILE="$CLAUDE_MD_FILE" python3 - <<PYEOF
import os
path = os.environ["CLAUDE_MD_FILE"]
with open(path) as f:
    content = f.read()

marker = "# Smart Model Router — Routing Protocol"
idx = content.find(marker)
if idx == -1:
    print("    Section not found.")
else:
    trimmed = content[:idx].rstrip("\n")
    with open(path, "w") as f:
        f.write(trimmed + "\n")
    print("    Removed.")
PYEOF
fi

echo ""
echo "Uninstallation complete. Restart Claude Code to apply changes."
