# omarchy-macdock

A macOS-style dock for [Omarchy](https://omarchy.org): a floating, rounded,
translucent panel at the bottom centre holding your apps, with magnification on
hover.

It is a third bar alongside
[`omarchy-winbar`](https://github.com/finleydavid2026-beep/omarchy-winbar) and
[`omarchy-mchotbar`](https://github.com/finleydavid2026-beep/omarchy-mchotbar),
not a replacement — `switch.sh` flips between all three.

## What you get

- **The dock** — a floating pill with your app icons, centred at the bottom.
- **Magnification** — as the cursor moves across the dock, each icon scales up
  with a falloff based on its distance from the cursor and lifts slightly, the
  way the macOS dock does. Verified by forcing a cursor position and measuring
  the rendered icon heights.
- **Trash** — a separator and a trash icon at the right end.
- **Clock and tray** — kept on the right so system info stays visible. macOS
  puts these in a top menu bar; dropping them would lose the tray.

The bar itself is made transparent and tall enough that the dock reads as
floating above the bottom edge.

## Install

```bash
git clone https://github.com/finleydavid2026-beep/omarchy-macdock.git
cd omarchy-macdock
./install.sh
```

The dock is seeded from the Omarchy hotbar's pins (or the Minecraft bar's app
list, if the hotbar is not on screen). Edit it any time:

```bash
nano ~/.config/omarchy/macdock/pins.json
```

It is a plain array of desktop ids — `["chromium", "steam", "localsend"]`. A
`class:org.foo.Bar` pin is resolved back to a desktop id by matching a dotted
segment.

## Switching bars

```bash
./switch.sh macdock    # macOS dock
./switch.sh mchotbar   # Minecraft hotbar (hearts = battery, armour = wifi)
./switch.sh winbar     # Windows-style taskbar
```

Each bar's layout is snapshotted the first time it runs, and `switch.sh` hands
off to the owning plugin's installer when a layout has never been stored — so
you can switch to a bar you have not installed yet and it installs itself.

## Uninstall

```bash
./uninstall.sh
```

Restores `shell.json` and `shell.toml` from the backups taken at install time
and deletes the plugin. Your app list at `~/.config/omarchy/macdock/pins.json`
is left in place.

## Notes for anyone extending this

- **A bar-widget plugin does not get `shell.appLibrary`.** The shell only hands
  that to plugins whose manifest declares the `"menu"` kind, so a bar-widget
  gets `null` there. Use Quickshell's global `DesktopEntries` singleton
  instead — `DesktopEntries.applications.values` gives the same entries with
  `.id`, `.name`, `.icon`, `.noDisplay` and an `.execute()` method.
- **No blur.** Omarchy's shell has no blur effect available, so the dock is
  translucent rather than frosted. A translucent pill still reads as a dock.
- **The dock is a bar widget, not its own window.** Omarchy's bar is already a
  bottom strip, so making its background transparent and putting the dock in the
  centre gives the floating look without a second layer-shell surface — and
  without fighting the bar for input.
