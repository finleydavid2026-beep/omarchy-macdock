#!/usr/bin/env bash
# Remove the macOS dock and put the previous bar back.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
LAYOUTS="$STATE/macdock"
PLUGIN_DIR="$OMARCHY_CONFIG/plugins/macdock"
PIN_DIR="$OMARCHY_CONFIG/macdock"
OTHER="prev"

say() { printf '%s\n' "$*"; }

# ------------------------------------------------------------ 1. plugin off
say "disabling the plugin"
for i in 1 2 3 4 5; do omarchy plugin disable macdock >/dev/null 2>&1 && break; sleep 1; done

# ------------------------------------------------------------- 2. configs
say "restoring the previous bar"
if [[ -f "$STATE/shell.json.macdock-bak" ]]; then
  cp "$STATE/shell.json.macdock-bak" "$OMARCHY_CONFIG/shell.json"
  say "  shell.json restored from backup"
elif [[ -f "$LAYOUTS/shell.json.$OTHER" ]]; then
  cp "$LAYOUTS/shell.json.$OTHER" "$OMARCHY_CONFIG/shell.json"
  say "  shell.json restored from the $OTHER snapshot"
else
  say "  no backup found; leaving shell.json as-is"
fi

if [[ -f "$STATE/shell.toml.macdock-bak" ]]; then
  cp "$STATE/shell.toml.macdock-bak" "$OMARCHY_CONFIG/shell.toml"
  say "  shell.toml restored from backup"
elif [[ -f "$LAYOUTS/shell.toml.$OTHER" ]]; then
  cp "$LAYOUTS/shell.toml.$OTHER" "$OMARCHY_CONFIG/shell.toml"
  say "  shell.toml restored from the $OTHER snapshot"
else
  say "  no backup; leaving shell.toml as-is"
fi

# ------------------------------------------------------------- 3. cleanup
if [[ -d "$PLUGIN_DIR" ]]; then
  rm -rf "$PLUGIN_DIR"
  say "removed $PLUGIN_DIR"
fi

say "applying"
for i in 1 2 3 4 5; do omarchy-shell shell reloadConfig >/dev/null 2>&1 && break; sleep 1; done
for i in 1 2 3 4 5; do omarchy restart shell >/dev/null 2>&1 && break; sleep 1; done

cat <<EOF

Removed.

The dock's app list is still at $PIN_DIR/pins.json if you want it back later.
EOF
