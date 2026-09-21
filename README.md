# TouchBarStatus

Shows which app currently has keyboard focus, on the macOS Touch Bar.

Built for a MacBook Pro whose **main display is dead**. The Touch Bar is a
separate panel that still works, so it can answer "where am I?" while
cmd-tabbing blind.

![Touch Bar showing the focused app](docs/screenshot.png)

## What it does

Two surfaces, because the Control Strip is too narrow for a readable name:

1. **A permanent icon in the Control Strip** — right-hand side, always
   visible, and it coexists with whatever Touch Bar the focused app draws on
   the left.
2. **A full-width flash on every app switch** — the icon plus the *full* app
   name in large text, which auto-dismisses after 1.5s and hands the bar back
   to the app.

The Control Strip only grants a fixed ~64pt slot per item (raising the width
constraint from 132pt to 220pt changes nothing — verified), which fits an icon
but truncates "Brave Browser" to `B...`. Hence the flash.

## Requirements

- A Mac with a Touch Bar
- macOS 11+ (developed and verified on macOS 26.4.1, Apple M1)
- Xcode Command Line Tools (`xcode-select --install`)

Builds as a **universal binary** (`x86_64` + `arm64`). Most Touch Bar Macs are
Intel, so the Intel slice matters more than the Apple Silicon one.

## Permissions

**None.** `NSWorkspace`'s `frontmostApplication` and its activation
notifications are unprivileged — no Accessibility, no Screen Recording, no
prompts to click through. This was a hard requirement: on a machine with a
dead screen you cannot grant permissions in System Settings.

## Install

```sh
./TouchBarStatus/install.sh
```

Builds the app, copies it to `~/Applications`, and registers a LaunchAgent so
it starts at login and restarts if it ever exits.

```sh
./TouchBarStatus/uninstall.sh
```

Removes all of it.

## Configuration

Everything is settable from a shell — deliberately, since this runs on a
machine where System Settings may be unreachable. Changes apply **live**, with
no restart.

| Key | Default | Meaning |
| --- | --- | --- |
| `FlashEnabled` | `YES` | Show the full-width name flash on app switch |
| `FlashDuration` | `1.5` | Seconds the flash stays up (0.2–10) |
| `TrayIconSize` | `24` | Control Strip icon size in points (8–30) |
| `FlashIconSize` | `26` | Flash icon size in points (8–30) |
| `FlashFontSize` | `18` | Flash label size in points (8–26) |
| `ReassertInterval` | `15` | Seconds between Control Strip presence checks; `0` disables |

```sh
defaults write com.tarik.touchbarstatus FlashDuration -float 2.5
defaults write com.tarik.touchbarstatus FlashEnabled -bool NO     # icon only
defaults delete com.tarik.touchbarstatus                          # back to defaults
```

## Build only

```sh
./TouchBarStatus/build.sh     # -> TouchBarStatus/build/TouchBarStatus.app
open TouchBarStatus/build/TouchBarStatus.app
```

## How it works

macOS exposes the Control Strip through the private `DFRFoundation`
framework. Three private entry points do the work:

| Symbol | Purpose |
| --- | --- |
| `DFRElementSetControlStripPresenceForIdentifier` | Registers our item into the Control Strip |
| `+[NSTouchBarItem addSystemTrayItem:]` | Supplies the view for that item |
| `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]` | Takes over the full bar for the name flash |

These are undocumented and Apple can change them at any time. They are
verified working on macOS 26.4.1; `build.sh` links the stubs shipped in the
Command Line Tools SDK at
`$(xcrun --show-sdk-path)/System/Library/PrivateFrameworks`.

Focus tracking itself is entirely public API:
`NSWorkspaceDidActivateApplicationNotification`.

### Control Strip re-registration

`ControlStrip.app` drops third-party registrations when it restarts, which
would leave the Touch Bar silently empty. Three overlapping defences:

1. Presence is re-asserted on every app switch (cheap, idempotent).
2. A timer re-asserts every `ReassertInterval` seconds.
3. That same timer watches `ControlStrip.app`'s **pid**. A change means it
   restarted, and the tray item is fully reinstalled (view and all).

Step 3 polls rather than observing a notification because
`NSWorkspaceDidLaunchApplicationNotification` is **not** posted for background
agents like ControlStrip — verified by killing ControlStrip and watching the
observer never fire. Recovery is verified: killing ControlStrip produces
`ControlStrip restarted (39804 -> 40412)` followed by `tray item reinstalled`.

## Developer tools

`TouchBarStatus/tools/` holds the QA harness used to develop this without a
working screen:

```sh
cd TouchBarStatus
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa \
  -framework CoreGraphics -framework CoreImage -o tools/capture tools/capture.m

./tools/verify.sh /tmp/tb.png    # waits for a keypress, then screenshots the Touch Bar
```

`capture.m` grabs the Touch Bar panel itself via `DFRDisplayStreamCreate` and
writes a PNG — genuinely useful, since `screencapture` cannot see the Touch
Bar.

**Note:** `DFRElementGetControlStripPresenceForIdentifier` is not a usable
readback — it returns 0 even immediately after a successful
`...SetControlStripPresence...` call, both in-process and cross-process. There
is no way to query whether the item is really there; only a screenshot tells
you.

**Note:** the Touch Bar panel dims after ~75s without real HID input, and
captures come back solid black when it does. `tools/wake.m` attempts to relight
it via `DFRBrightnessClientDisplayTurnOn`; the calls all report success but the
panel stays dark, so `verify.sh` waits for genuine input instead. This only
affects screenshotting — in normal use you are touching the keyboard, so the
bar is lit.

## Layout of this repo

```
TouchBarStatus/
  src/main.m        the app
  build.sh          builds the .app bundle
  install.sh        build + install + LaunchAgent
  uninstall.sh      remove everything
  tools/            Touch Bar capture / wake / verify harness
spike/              throwaway proof-of-concept that the private API still works
```

## License

MIT
