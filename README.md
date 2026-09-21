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

`ControlStrip.app` drops third-party registrations when it restarts, so the
app re-asserts its presence on every app switch. Cheap and idempotent.

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
