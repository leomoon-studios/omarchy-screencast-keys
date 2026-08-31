# Omarchy Screencast Keys

An Omarchy Shell plugin by LeoMoon Studios that displays pressed keys in a
click-through overlay. Chords are shown as individual rounded keycaps, such as
`[SUPER] + [L]`. Up to seven entries are kept on screen and each fades out
after two seconds.

## Features

- Four positions: top-left, top-right, bottom-left, and bottom-right
- Overall size control from 60% to 200%
- Display duration control from 1 to 10 seconds, defaulting to 3 seconds
- On/off switch that stops input capture without removing the bar icon
- Theme-aware Omarchy keycaps on every monitor
- No Omarchy service entry point; a keep-loaded overlay owns the controller
- No key history or captured text is written to disk

## Install

Once the repository is published, install and enable it with:

```bash
omarchy plugin add <git-url> --enable
```

For local development, copy this repository to the user plugin directory,
rescan, then enable it:

```bash
plugin_dir="$HOME/.config/omarchy/plugins/leomoon-studios.omarchy-screencast-keys"
mkdir -p "$(dirname "$plugin_dir")"
cp -a . "$plugin_dir"
omarchy-shell shell rescanPlugins
omarchy plugin enable leomoon-studios.omarchy-screencast-keys --section right
```

The plugin stores preferences at:

```text
~/.config/leomoon-studios.omarchy-screencast-keys/settings.json
```

## Input access

Wayland does not let an ordinary overlay observe keys typed into other apps.
The plugin's bundled reader therefore opens Linux keyboard event devices
read-only. If access is unavailable, open the bar menu and click **Grant input
access**. This presents a PolicyKit authorization dialog and installs a udev
rule for keyboard event devices. The plugin never requests privileges during
startup.

To remove that permission later:

```bash
sudo ./scripts/input-access.sh remove
```

The reader sends key labels only to the running Omarchy Shell process. It does
not create a log or store key history. Global capture can still observe keys
entered into password fields, so switch the plugin off whenever it is not
needed.

## Controls

- Left-click the keyboard icon to open settings.
- Right-click the icon to quickly turn capture on or off.
- Use the position buttons, size slider, and duration slider in the settings
  popup.

## Test and validate

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -v
python3 scripts/key-reader.py --demo
```

The `demo` IPC method previews the overlay without input permission:

```bash
omarchy-shell leomoon-studios.omarchy-screencast-keys demo
```

## Compatibility note

Version 1 displays physical Linux key-code labels. Letter and punctuation
labels therefore follow the standard physical layout rather than translating
through the currently selected keyboard layout.

See [PLUGIN.md](PLUGIN.md) for the design and acceptance criteria.
