# Controllers

vjag uses SDL3's gamepad drivers and mappings. Pair Bluetooth controllers in the
operating system first, or connect them by USB. The first two recognised
controllers get Jaguar ports 1 and 2; keyboard and shell-keypad input also go
to player 1. A waiting third controller can take a vacant port.

The software paths have been tested with SDL virtual controllers on macOS and
SDL 3.4.18. Helge also confirmed that his Xbox 360 controller works through its
USB wireless receiver using an SDL build with libusb support. Physical PS3,
PS4, PS5, and other USB/Bluetooth devices still need testing. In particular,
PS3 pairing and drivers vary by operating system. vjag
does not install drivers or change SDL's normal driver selection. The primary
sources and protocol findings are in [the research note](gamepad-support-research.md).

## Default layout

| Jaguar | Gamepad | PlayStation |
| --- | --- | --- |
| Direction | D-pad or left stick | D-pad or left stick |
| C, B, A | West, South, East | Square, Cross, Circle |
| Option | North or Back | Triangle or Select/Share/Create |
| Pause | Start | Start/Options |
| `*`, `#` | Left, right shoulder | L1, R1 |
| Keypad layer | Hold left trigger | Hold L2 |

While the keypad is visible, use the d-pad or right stick to select a key.
Hold South/Cross to press it; release to let go. A held key stays the same even
if you move the selection. Releasing the layer shortcut releases its key too.
Navigation and confirmation are consumed by the layer, so they do not move the
player or fire B. The game continues running; the left stick remains available
for movement. Rebind the layer shortcut to a button/chord if the pad has no
trigger. Its binding must leave South, the d-pad and right-stick directions free
for keypad navigation/confirmation. Direct bindings are available for frequent keypad actions or games
that need simultaneous keypad keys.

Sticks activate at 30% travel and release below 20% by default. Separate on/off
thresholds prevent drift around the boundary from repeatedly pressing a
direction. Held keyboard, d-pad and stick bindings are combined: releasing one
does not cancel another that is still held.

## Controls screen

Press **K**. The controls screen pauses guest execution while open; closing it
restores the previous pause state. Configuration is operated from the keyboard.

| Key | Action |
| --- | --- |
| K / Esc | Close; Esc cancels an in-progress capture first |
| Tab | Select player 1 or 2 |
| Up / Down | Select a binding, dead zone, or device row |
| Enter | Replace a binding: hold the desired control/chord, then release |
| A | Add an alternative binding instead of replacing |
| Backspace | Clear the selected binding |
| Left / Right | Adjust the dead zone on its row |
| D | Cycle connected gamepads; swaps players when the chosen pad is assigned |
| G | Switch between global and current-game editing, when a game is loaded |
| R | Restore default bindings/dead zone for the selected scope/player |
| I | Remove the current game's override and inherit global settings |
| L | Reload the optional SDL mapping file |

Changes save automatically. A game profile is a full copy of the selected
player's bindings, identified by the normalized image hash, so renaming the ROM
does not lose its settings. Global edits do not change an existing game
override; select the game scope and press I to inherit again.

The panel shows the assigned controller, physical face-button labels where SDL
knows them, held controls, available button/axis counts, mapping GUID, connection
state and battery estimate. "Wireless" does not necessarily mean Bluetooth; a
wireless receiver may use another protocol. Unknown battery/transport remains
unknown. Unmapped joysticks show their names and GUIDs.

Disconnecting a controller releases only its inputs. Focus loss, reassignment,
reset and cartridge changes clear live inputs. Held controls must return to
neutral before they act again. Scripted `--press-file` input retains exclusive
ownership of guest buttons, including across these transitions.

## Configuration files and generic controllers

Controller preferences are in `vjag/controllers.toml` within the OS configuration
directory (`~/Library/Application Support` on macOS). They are separate from
the window preferences in `config.toml`. Profiles use physical positions, so
they work across Xbox-style and PlayStation labels and USB/Bluetooth mappings.
Device assignment preferences are best-effort: serial numbers may be absent and
identical controllers may need reassignment with D after reconnecting.

Known SDL gamepads need no extra mapping file. For an unknown joystick, put
valid SDL mapping lines in `vjag/gamecontrollerdb.txt` alongside the config and
press L, or restart. The platform/GUID must match the device; USB and Bluetooth
can need different entries. A mapping translates numbered device buttons,
hats and axes into standard SDL positions. See
[SDL's mapping format](https://wiki.libsdl.org/SDL3/SDL_AddGamepadMapping).
vjag does not guess the layout of an unknown joystick or automatically download
mapping databases.

Jaguar bindings are a separate layer. For example:

```toml
[profiles.global_1]
press = 30
release = 20
b = "south"
one = "righttrigger"
two = "rightshoulder+south"
keypad = "lefttrigger|leftstick"
```

`+` means a chord; `|` means alternatives. Empty strings unbind a target;
missing targets use defaults. Active chords take precedence over their
individual button bindings. For a dedicated modifier, clear its ordinary
Jaguar binding too, so pressing the modifier alone does not trigger that
action. Two targets may share a chord for simultaneous keypad presses.

Targets are `up`, `down`, `left`, `right`, `a`, `b`, `c`, `option`, `pause`,
`zero` through `nine`, `star`, `hash`, and `keypad` (the layer shortcut).
Controls include `south`, `east`, `west`, `north`, `back`, `start`, `guide`,
`leftstick`, `rightstick`, `leftshoulder`, `rightshoulder`, `dpup`, `dpdown`,
`dpleft`, `dpright`, `touchpad`, `lefttrigger`, `righttrigger`, and axis directions
such as `leftx_neg`, `leftx_pos`, `lefty_neg`, `righty_pos`. Additional SDL
buttons include `misc1`–`misc6`, `leftpaddle1/2` and `rightpaddle1/2`.

Edit files while the app is closed. Invalid bindings/dead zones fall back to
defaults with a notice in Controls. An unreadable TOML file is preserved and
cannot be overwritten from the screen until repaired. Connection diagnosis:

- **No devices visible:** check host pairing, power and USB cable/receiver.
- **Needs mapping:** SDL sees a joystick; provide the appropriate mapping.
- **Mapped but unexpected actions:** check player assignment, active game
  profile, bindings and live input indicators.

## Xbox 360 wireless receiver on this Mac

A hardware check on 2026-11-17 found Microsoft's USB wireless receiver
`045e:0719` on macOS 15.6. The installed Homebrew SDL 3.4.18 detected zero
receiver interfaces and zero joysticks. Its Xbox 360 wireless driver was
present, but the libusb backend was absent; enabling runtime libusb hints did
not change detection. libusb 1.0.30 was already installed.

Building the same SDL release locally with `-DSDL_HIDAPI_LIBUSB=ON` changed the
result to four receiver interfaces and one mapped **Xbox 360 Wireless
Controller**. Opening it succeeded and exposed 15 buttons and 6 axes with a
wireless connection state. Helge then confirmed the controller works in the
emulator. No kernel driver or new
controller protocol implementation was needed: SDL already provides the
[Xbox 360 wireless driver](https://github.com/libsdl-org/SDL/blob/release-3.4.18/src/joystick/hidapi/SDL_hidapi_xbox360w.c),
and its [libusb backend](https://wiki.libsdl.org/SDL3/SDL_HINT_HIDAPI_LIBUSB)
provides direct USB access when compiled in.

The permanent setup is:

```sh
brew install cmake pkgconf libusb
just setup-sdl-usb
just run
```

Press K to inspect the controller. Setup downloads SDL 3.4.18 from its official
release, verifies its SHA-256, and builds it with libusb enabled and linked
directly. The private install is under `~/.local/lib/vjag/`, with the version,
OS and architecture in its directory name. It survives `just clean`; normal
`just` build, run, test and install commands select it automatically. Executables
embed its library path, so no `DYLD_LIBRARY_PATH` is needed, including after
`just install`. Keep libusb installed and keep that private SDL directory.

Set `VJAG_SDL_PREFIX` for a different SDL installation prefix and
`VJAG_BUILD_JOBS` to change build parallelism. Without a private install, builds
continue to use system SDL. The earlier diagnostic files in
`out/xbox360-check/` are no longer needed to run the app. A gamepad mapping file
alone cannot repair a missing USB backend.
