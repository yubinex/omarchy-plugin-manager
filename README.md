# Omarchy Plugin Manager

An Omarchy bar plugin for switching many shell plugins on and off at once.

Click the puzzle piece for a panel listing your installed plugins. Flip as many
switches as you like; nothing changes until you press **APPLY**, and
**REVERT** throws the staged changes away.

With nothing staged, that button becomes **UNDO**: it reverses the last
apply, even after the panel was closed.

## Re-enabled widgets come back where they were

Disabling a bar widget normally deletes its entry from `shell.json`, position
and settings included, and enabling it again drops a bare entry at the
default spot. This plugin remembers each bar widget's section, neighbours
and inline settings whenever the layout changes, however the widget was
disabled (this panel, `omarchy plugin disable`, or a manual edit). Enabling
it from the panel puts it back beside the same neighbour (or at the same
index if that neighbour is gone) and restores its settings.

Positions live in `~/.local/state/omarchy-plugin-manager/positions.json`.

## What is listed

- Your installed plugins: bar widgets, services, panels and overlays.
- Built-in bar widgets, behind the **BUILT-IN** toggle.
- Built-in services (lock screen, polkit agent, notifications, …) are left
  out on purpose. Use `omarchy plugin disable` if you really mean it.

## Installation

```bash
omarchy plugin add https://github.com/yubinex/omarchy-plugin-manager.git --enable
```

Needs only `python3`, which Omarchy already depends on.

## Removal

```bash
omarchy plugin remove yubinex.plugin-manager
```

Plugins you switched off stay off. To also forget the remembered positions,
delete `~/.local/state/omarchy-plugin-manager/`.

## What it changes

Your configuration only changes when you press **APPLY**, and only through
Omarchy's own `omarchy plugin enable|disable` and `omarchy bar set` commands.
Between applies the plugin only reads `shell.json` and writes its own state
directory.

## How it works

`bin/plugin-manager` does the work through the regular `omarchy plugin` and
`omarchy bar set` commands. Adding or removing a bar entry rebuilds every
bar widget, the panel included, so APPLY runs it detached; it reopens the
panel when done, and the panel reports the outcome.

## License

[MIT](LICENSE)
