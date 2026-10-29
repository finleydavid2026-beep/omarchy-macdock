#!/usr/bin/env bash
# Install the macOS-style dock.
#
# The dock is a bar widget, so installing it means making the bar transparent
# and tall enough that the dock reads as floating, and putting the dock in the
# centre section.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
PLUGIN_DIR="$OMARCHY_CONFIG/plugins/macdock"
PIN_DIR="$OMARCHY_CONFIG/macdock"
LAYOUTS="$STATE/macdock"
SELF="macdock"
OTHER="prev"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for cmd in omarchy omarchy-shell; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found — is Omarchy installed?"
done

mkdir -p "$STATE" "$LAYOUTS" "$PIN_DIR"

# ---------------------------------------------------------------- 1. back up
# Before anything touches the config: `omarchy plugin enable` writes the widget
# into shell.json, so a backup taken afterwards would already contain this
# plugin's own changes.
if (( !DRY_RUN )); then
  for f in shell.json shell.toml; do
    if [[ -f "$OMARCHY_CONFIG/$f" && ! -f "$STATE/$f.macdock-bak" ]]; then
      cp "$OMARCHY_CONFIG/$f" "$STATE/$f.macdock-bak"
      say "backed up $f"
    fi
  done
fi

# ------------------------------------------------------- 2. keep the old bar
# Snapshot whatever is running so switch.sh can bring it back. Only the first
# snapshot is kept, so switching back restores the original.
if (( !DRY_RUN )); then
  for f in shell.json shell.toml; do
    if [[ -f "$OMARCHY_CONFIG/$f" && ! -f "$LAYOUTS/$f.$OTHER" ]]; then
      cp "$OMARCHY_CONFIG/$f" "$LAYOUTS/$f.$OTHER"
      say "snapshotted the current bar as $f.$OTHER"
    fi
  done
fi

# ---------------------------------------------------------------- 3. plugin
say "installing plugin"
if (( DRY_RUN )); then
  say "  would copy the plugin to $PLUGIN_DIR"
else
  mkdir -p "$PLUGIN_DIR"
  cp "$REPO/manifest.json" "$REPO/Dock.qml" "$PLUGIN_DIR/"
  cp -r "$REPO/assets" "$PLUGIN_DIR/"
fi

# ------------------------------------------------------------- 4. app list
# Seed the dock from the Omarchy hotbar's pins, so the apps you already pinned
# are in the dock on the first run.
if (( !DRY_RUN )) && [[ ! -f "$PIN_DIR/pins.json" ]]; then
  # Prefer the Omarchy hotbar's pins; fall back to the Minecraft bar's list,
  # which is where the apps already are if the hotbar is not on screen.
  if command -v hotbar >/dev/null 2>&1 && hotbar state >/dev/null 2>&1; then
    hotbar state 2>/dev/null | python3 -c "
import json, sys
json.dump(json.load(sys.stdin).get('pins', []), open('$PIN_DIR/pins.json', 'w'), indent=2)
" >/dev/null 2>&1 && say "seeded the dock from the Omarchy hotbar pins"
  fi
  if [[ ! -f "$PIN_DIR/pins.json" && -f "$OMARCHY_CONFIG/mchotbar/pins.json" ]]; then
    cp "$OMARCHY_CONFIG/mchotbar/pins.json" "$PIN_DIR/pins.json"
    say "seeded the dock from the Minecraft bar's app list"
  fi
  if [[ ! -f "$PIN_DIR/pins.json" ]]; then
    printf '[]\n' > "$PIN_DIR/pins.json"
    say "no hotbar pins found; wrote an empty dock"
  fi
fi

# ------------------------------------------------------------ 5. bar layout
say "writing the macOS dock layout"
if (( !DRY_RUN )); then
  python3 - "$OMARCHY_CONFIG/shell.json" "$LAYOUTS/shell.json.$SELF" <<'PY'
import json, sys, pathlib

path = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

cfg = json.loads(path.read_text())
bar = cfg.setdefault("bar", {})
layout = bar.setdefault("layout", {})

# The dock replaces the whole centre. The clock and tray stay on the right so
# system info is still visible; macOS puts the clock in a top menu bar, but
# dropping it entirely would lose the tray.
left = []
# The clock usually lives in the centre section of the other bar layouts, so
# pull it out of the centre as well or it would be dropped when the centre is
# replaced by the dock.
clock = next((e for e in layout.get("center", []) if isinstance(e, dict) and e.get("id") == "omarchy.clock"), None)
if clock is None:
    clock = next((e for e in layout.get("right", []) if isinstance(e, dict) and e.get("id") == "omarchy.clock"), None)
# The dock carries its own system-control icons, so the right section only
# needs the clock, tray, and indicators.
keep = {e["id"]: e for e in right if isinstance(e, dict) and e.get("id") in ("omarchy.tray", "omarchy.indicators")}
right = []
right += ([clock] if clock is not None else [{"id": "omarchy.clock"}])
right += [keep.get("omarchy.tray", {"id": "omarchy.tray"})]

layout["left"] = left
layout["center"] = [{"id": "macdock"}]
layout["right"] = right
bar["centerAnchor"] = ""
bar["transparent"] = True

path.write_text(json.dumps(cfg, indent=2) + "\n")
out.write_text(json.dumps(cfg, indent=2) + "\n")
print("  centre: macdock   (bar transparent)")
PY

  # The dock is a floating pill, so the bar has to be transparent and tall
  # enough to leave a margin above and below it.
  python3 - "$OMARCHY_CONFIG/shell.toml" "$LAYOUTS/shell.toml.$SELF" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
text = path.read_text() if path.exists() else ""

block = """
# macOS dock: transparent bar with room for the floating pill.
[bar]
background = "#000000"
background-alpha = 0.0
size-horizontal = 92
size-vertical = 92
icon-slot = 60
icon-canvas = 48
icon-font = 24
status-slot = 36
"""

lines = text.split("\n")
start = next((i for i, l in enumerate(lines) if l.strip() == "[bar]"), None)
if start is None:
    text = text.rstrip("\n") + "\n" + block
else:
    end = start + 1
    while end < len(lines) and not lines[end].startswith("["):
        end += 1
    text = "\n".join(lines[:start]) + "\n" + block + "\n".join(lines[end:])

path.write_text(text)
out.write_text(text)
print("  bar: transparent, 92px tall")
PY

  # ------------------------------------------------------------- 6. enable
  for i in 1 2 3 4 5; do omarchy plugin enable macdock >/dev/null 2>&1 && break; sleep 1; done
  for i in 1 2 3 4 5; do omarchy-shell shell reloadConfig >/dev/null 2>&1 && break; sleep 1; done
  for i in 1 2 3 4 5; do omarchy restart shell >/dev/null 2>&1 && break; sleep 1; done
fi

cat <<EOF

Done. The macOS dock is live.

  dock        macdock     click an icon to launch; icons magnify on hover
  trash       right end   opens the trash folder

Change the dock contents:
  nano ~/.config/omarchy/macdock/pins.json

Switch to another bar:
  $REPO/switch.sh winbar
  $REPO/switch.sh mchotbar

Undo completely:
  $REPO/uninstall.sh
EOF
