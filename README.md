# <img src="icon.png" width="40" align="top"> nommarchy

Razer Nommo V2 X control panel for [Omarchy](https://omarchy.org/) (Linux).

A native port of the macOS [nommac](https://github.com/pablopunk/nommac)
menu-bar app. It talks directly to the speakers' vendor HID interface over
USB — the same 90-byte feature-report protocol (report ID `0x07`) that Razer
Synapse uses on Windows — so you get every setting Synapse has with no
Synapse, no drivers, and no bloat.

![nommarchy](preview.png)

| Setting        | Supported |
|----------------|-----------|
| 10-band EQ     | ✅ 31 Hz – 16 kHz, ±12 dB |
| EQ presets     | ✅ Flat / Game / Movie / Music |
| Eco mode       | ✅ power saving toggle |
| Sleep timeout  | ✅ including *Never* (stop the speakers sleeping mid-song) |

Settings are written to the speaker firmware, so they **persist across
reboots and re-plugs**.

## Install

### 1. Add the shell plugin

```bash
omarchy plugin add https://github.com/pablopunk/nommarchy.git
```

### 2. Install the backend + udev rule

The plugin drives the tiny `nommarchy` CLI, plus a udev rule that grants your
user unprivileged access to the speakers' HID interface:

```bash
cd ~/.config/omarchy/plugins/pablopunk.nommarchy
./install.sh
```

The installer runs as *you* (no `sudo`): it copies `nommarchy` to
`~/.local/bin/nommarchy`, and elevates **only** the udev-rule installation
(the rule write plus a udev reload/trigger) via `sudo`/`pkexec`.

> The plugin runs unsandboxed inside the Omarchy shell (like any shell
> plugin) and shells out to `nommarchy`. It never touches the network, never
> records, and only writes to the speakers when you interact with it.

#### Security note

Only the udev rule needs root, so `install.sh` keeps the privileged step to a
single, *fixed* file write: the rule is embedded in the script as a literal
string (see `install_udev` in `install.sh`, mirroring `99-nommo.rules`) and
written via `sudo tee`, followed by a standard udev reload/trigger. Nothing is
copied out of the user-writable plugin checkout into a system location, and the
CLI is installed user-locally — so a process running as your user cannot
influence what gets written as root.

## Usage

**Launch it like an app** — from the Omarchy menu (search **Nommarchy**) or
click the **equalizer icon** in the bar:

- **left-click** the bar icon → open/close the panel
- **Quit** button in the panel → remove the icon from the bar
- **launch from the menu** → re-add the icon if it was quit, then open the panel

In the panel:

- **drag** a vertical bar → edit that band
- **right-drag** → shift the whole 10-band curve at once
- **double-click** a bar → reset that band to 0 dB
- **double right-click** → flatten all ten bands
- **scroll** a bar → nudge it ±1 dB
- **↑/↓** nudge the focused band, **←/→** move focus, **Esc** closes

You can also toggle it from a terminal or a keybind:

```bash
omarchy-shell shell toggle pablopunk.nommarchy
```

The `nommarchy` binary doubles as a command-line tool (ensure `~/.local/bin`
is on your `PATH`):

```bash
nommarchy status                      # show all settings
nommarchy eco on|off                  # power saving (auto sleep)
nommarchy sleep 30 | sleep off        # idle sleep timeout in minutes
nommarchy eq show | eq flat           # current 10-band EQ / reset to 0 dB
nommarchy eq min                      # every band at the -12 dB floor
nommarchy eq 4 3 2 0 0 0 0 1 2 3      # set bands: 31 63 125 250 500 1k 2k 4k 8k 16k
nommarchy preset music                # flat|game|movie|music
nommarchy json                        # machine-readable state (for the shell)
```

## How it works

The Nommo V2 X exposes a vendor HID feature report (report ID `0x07`, 90
bytes) alongside its USB audio. `nommarchy` writes a request and reads the
staged response over `/dev/hidraw*` using the standard `HIDIOCSFEATURE` /
`HIDIOCGFEATURE` ioctls — no third-party libraries. Protocol reverse
engineered in [openrazer#2758](https://github.com/openrazer/openrazer/issues/2758).

| Setting | Command |
|---------|---------|
| Eco mode | `0x07/0x08` (read `0x88`) |
| Sleep timeout | `0x07/0x03` (read `0x83`, big-endian seconds; writing re-enables eco, so it is saved/restored) |
| 10-band EQ | `0x08/0x04` (read `0x84`; `0x0C` = 0 dB, one unit per dB) |
| EQ preset | `0x08/0x02` (read `0x82`; 0–3, `0x10` = custom) |

Master volume is deliberately not exposed: it is the USB audio volume, which
the OS already controls.

> **Presets:** the flat/game/movie/music curves are firmware built-ins that the
> device does *not* expose over HID — only the custom 10-band curve is readable.
> Selecting a preset therefore shows the bars reset to flat (matching the macOS
> app's behaviour); the bars reflect the real editable curve once you drag a
> band and the device switches to Custom.

## Uninstall

```bash
omarchy plugin remove pablopunk.nommarchy
cd ~/.config/omarchy/plugins/pablopunk.nommarchy 2>/dev/null && ./install.sh --uninstall
# or by hand:
rm -f ~/.local/bin/nommarchy
sudo rm -f /etc/udev/rules.d/99-nommo.rules
```

## License

[MIT](LICENSE) — derived from [nommac](https://github.com/pablopunk/nommac).
