# Omarchy Screencast Keys

An Omarchy Shell plugin by LeoMoon Studios that displays pressed keys in a click-through overlay. Keyboard and mouse-button chords are shown as individual rounded keycaps, such as `[SUPER] + [L]` or `[SUPER] + [RMB]`. Up to the configured number of entries (seven by default) are kept on screen and each fades out after the configured duration.

Requires Omarchy 4.0 or newer. Other desktops and standalone Quickshell configurations are not supported.

## Features

- Four positions: top-left, top-right, bottom-left, and bottom-right
- Overall size control from 60% to 200%
- Display duration control from 1 to 10 seconds, defaulting to 3 seconds
- Visible stack size control from 1 to 15 entries, defaulting to 7
- Left, middle, and right mouse buttons shown as LMB, MMB, and RMB
- On/off switch that stops input capture without removing the bar icon
- Capture defaults to off when settings are missing or malformed
- Theme-aware Omarchy keycaps on every monitor
- No Omarchy service entry point; a keep-loaded overlay owns the controller
- No key history or captured text is written to disk

## Install

Install and enable the plugin from GitHub with:

```bash
omarchy plugin add https://github.com/leomoon-studios/omarchy-screencast-keys.git --enable
```

Omarchy installs the repository into:

```text
~/.config/omarchy/plugins/leomoon-studios.omarchy-screencast-keys/
```

The widget defaults to the right section of the bar. It can be moved with the normal Omarchy bar controls.

The plugin stores preferences at:

```text
~/.config/leomoon-studios.omarchy-screencast-keys/settings.json
```

## Removal

Unload the plugin and remove its installed checkout:

```bash
omarchy plugin remove leomoon-studios.omarchy-screencast-keys --yes
```

Omarchy intentionally leaves the plugin's settings in place so they remain available after a reinstall. To permanently remove those settings too:

```bash
rm -rf ~/.config/leomoon-studios.omarchy-screencast-keys
```

## Input access

Wayland does not let an ordinary overlay observe keys typed into other apps. The plugin's bundled reader therefore opens Linux keyboard and pointer event devices read-only using access already available to the Omarchy session. The plugin does not request elevated privileges or install udev rules. If input devices are unavailable, the menu reports **Global input access unavailable** without changing the system.

Capture starts disabled on a fresh installation and remains disabled if the settings file is missing or malformed.

The reader sends key and mouse-button labels only to the running Omarchy Shell process. It does not create a log or store key history. Global capture can still observe keys entered into password fields, so switch the plugin off whenever it is not needed.

## Controls

- Left-click the SCK badge to open settings.
- Right-click the icon to quickly turn capture on or off.
- Use the position buttons, size slider, duration slider, and visible-keys
  slider in the settings popup.
- The popup stays open while global shortcuts are pressed, making it possible
  to include the menu in a screenshot or recording. Click outside it or click
  the badge again to close it.
- Omarchy's `SUPER+CTRL+1` through `SUPER+CTRL+9` shortcuts can open it by its
  numbered position among panel-capable icons in the bar's right section.

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

## Compatibility

Omarchy 4.0+ on Wayland is the only supported environment.

Version 1 displays physical Linux key-code labels. Letter and punctuation labels therefore follow the standard physical layout rather than translating through the currently selected keyboard layout.
