#!/usr/bin/env bash
# Switch between the bars.
#
#   switch.sh macdock    macOS-style dock
#   switch.sh mchotbar   Minecraft hotbar (hearts = battery, armour = wifi)
#   switch.sh winbar     Windows-style taskbar
#
# Each bar's layout is snapshotted the first time it is installed, so switching
# is just a copy back — no re-derivation, and switching back always restores
# what was actually running.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
LAYOUTS="$STATE/macdock"
OTHER="prev"

target="${1:-}"
case "$target" in
  winbar|mchotbar|macdock) ;;
  "") echo "usage: $(basename "$0") <winbar|mchotbar|macdock>" >&2; exit 2 ;;
  *) echo "unknown bar: $target (expected winbar, mchotbar or macdock)" >&2; exit 2 ;;
esac

say() { printf '%s\n' "$*"; }

# 1. Snapshot whatever is running right now under the "other" name.
if [[ -f "$OMARCHY_CONFIG/shell.json" ]]; then
  if [[ ! -f "$LAYOUTS/shell.json.$OTHER" ]]; then
    cp "$OMARCHY_CONFIG/shell.json" "$LAYOUTS/shell.json.$OTHER"
    say "snapshotted the running bar as $OTHER"
  fi
  if [[ ! -f "$LAYOUTS/shell.toml.$OTHER" ]]; then
    cp "$OMARCHY_CONFIG/shell.toml" "$LAYOUTS/shell.toml.$OTHER"
  fi
fi

# 2. Apply the target. If this plugin has never stored that bar's layout, hand
#    off to the plugin that owns it rather than reinstalling ourselves.
if [[ ! -f "$LAYOUTS/shell.json.$target" ]]; then
  case "$target" in
    mchotbar) sibling="$HOME/omarchy-mchotbar" ;;
    winbar)   sibling="$HOME/omarchy-winbar" ;;
    *)        sibling="$REPO" ;;
  esac
  if [[ -x "$sibling/install.sh" ]]; then
    say "no stored layout for $target — handing off to $sibling"
    exec "$sibling/install.sh"
  fi
  say "no stored layout for $target and no installer found at $sibling" >&2
  exit 1
fi

cp "$LAYOUTS/shell.json.$target" "$OMARCHY_CONFIG/shell.json"
cp "$LAYOUTS/shell.toml.$target" "$OMARCHY_CONFIG/shell.toml"
say "applied the $target layout"

# 3. Enable the matching plugin and disable the others, so only one is live.
case "$target" in
  macdock)   on="macdock" ;;
  mchotbar)  on="mchotbar" ;;
  winbar)    on="winbar" ;;
esac

for plugin in macdock mchotbar winbar; do
  if [[ "$plugin" == "$on" ]]; then
    for i in 1 2 3 4 5; do omarchy plugin enable "$plugin" >/dev/null 2>&1 && break; sleep 1; done
  else
    for i in 1 2 3 4 5; do omarchy plugin disable "$plugin" >/dev/null 2>&1 && break; sleep 1; done
  fi
done

for i in 1 2 3 4 5; do omarchy-shell shell reloadConfig >/dev/null 2>&1 && break; sleep 1; done
for i in 1 2 3 4 5; do omarchy restart shell >/dev/null 2>&1 && break; sleep 1; done

say "switched to $target"
