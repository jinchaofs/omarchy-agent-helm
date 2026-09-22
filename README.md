# Agent Helm

Bar panel for managing Omarchy's coding agents: open any installed agent,
move the default with a radio dot, install missing ones — all from one popup.

## Install

```bash
omarchy plugin add https://github.com/jinchaofs/omarchy-agent-helm.git --enable
```

Then press `SUPER + A` or click the 󰚩 icon in the bar.

## Remove

```bash
omarchy plugin remove jinchaofs.agent-switcher
```

Removes the widget from the bar and deletes the plugin folder. It never
touches `~/.config/omarchy/defaults/agent` or any agent installation; your
default agent and installed agents are left exactly as they were.

## Usage

| Gesture | Action |
|---|---|
| Click a row (installed) | Open that agent; the default stays untouched |
| Click the dot / `→` / `d` | Make it the default (notification confirms; launches nothing) |
| Click a row or **Install** (missing) | `omarchy-default-agent` install flow |
| Right-click the bar icon | Skip the panel: open the current default immediately |
| `Enter` / `↑` `↓` / `Esc` | Open / walk the list (wraps) / close |

## How it works

- **State** — `bin/agent-status` emits default + install status as JSON.
  Labels and icons are read from the stock menu table
  (`omarchy-menu.jsonc`, the same one Super+Space → Setup → Agent uses), so
  the panel never drifts from the system menu. Install detection mirrors
  `omarchy-default-agent`: hermes/openclaw answer through their installers
  (a bare `command -v` only sees a cold stub), everything else is a
  `~/.local/bin` user install or a mise package.
- **Open without changing the default** — `bin/agent-open` puts a session
  shim on PATH that answers `omarchy-agent`'s "who is the default?" with the
  clicked agent, then runs `omarchy-agent` (which owns the per-agent flags
  like `--auto` / `--yolo`). The real default file is never written, so no
  flag table is duplicated here.
- **Set default** — `bin/agent-set` writes the default and sends a desktop
  notification. It never installs or launches; that is the Install button's
  job (`omarchy-default-agent <id>`).

## Keyboard / IPC

```bash
omarchy-shell shell toggle jinchaofs.agent-switcher '{}'   # toggle the panel
```

Bound to `SUPER + A` in `~/.config/hypr/bindings.lua`.
`SUPER + SHIFT + CTRL + A` (stock) still launches the default agent directly.

## Layout

Installed agents first, then NOT INSTALLED. The cursor opens on the current
default, so `SUPER + A → Enter` launches it.

## Limits / future

- The shim is scoped to the session that created it: the panel, menu
  checkmarks, and the direct-launch binding keep showing the true default
  the whole time, and concurrent opens cannot race each other.
- Launching a second instance of an agent while one is open is up to the
  terminal/app-id behavior of `omarchy-agent`, not this panel.
- `agent-status` answers through each agent's own installer for
  hermes/openclaw and local PATH/mise checks for the rest; it never hits
  the network (`mise where` on http-backed packages such as muse can stall,
  which froze an earlier version of this panel).
