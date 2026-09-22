# TouchBarStatus — working notes

Shows which app has keyboard focus on the macOS Touch Bar. See `README.md`
for what it does and how it is built; this file is the things that will
waste your time if you do not know them.

## The constraint that drives every decision

This was built on a MacBook Pro (M1, 2020) whose **internal display is
dead**. The Touch Bar is a separate panel that still works, so it is the
only screen. Consequences:

- **Never require a permission that needs a click.** System Settings is
  unreachable. Every feature must work with no TCC grant, or degrade
  cleanly without one.
- **You cannot look at the result.** Verify with the tools below, and do
  not claim anything visual works until you have seen a captured frame.

## Verifying anything visual

`screencapture` cannot see the Touch Bar. `tools/capture.m` grabs the panel
itself via `DFRDisplayStreamCreate`:

```sh
./tools/capture /tmp/tb.png 2.0        # single frame
./tools/capture '/tmp/f%d.png' 8.0     # a sequence, one file per change
./tools/verify.sh /tmp/tb.png          # waits for a keypress first
```

**The panel dims after ~75s without real HID input, and captures come back
solid black.** This is the single most confusing failure mode here. Known
dead ends, both measured, do not retry them:

- `caffeinate -u` does not reset HID idle time (and `-u` without `-t`
  expires after 5 seconds anyway).
- `DFRBrightnessClientDisplayTurnOn` reports success and leaves the panel
  dark. That is what `tools/wake.m` is; it does not work.

So the capture scripts poll `ioreg -c IOHIDSystem | HIDIdleTime` and wait
for genuine input. If the user is not physically at the machine, a capture
will simply time out. That is expected, not a bug.

The stream only emits frames **on change**, so a static bar produces one
frame and then nothing.

## Testing without the Touch Bar

```sh
./build/TouchBarStatus.app/Contents/MacOS/TouchBarStatus --dump
```

Prints exactly what the picker would show — apps, processes, window titles
— from a shell. Use this for anything data-related; it needs no panel and
no taps. `SIGUSR1` opens the picker without a tap.

Logs: launched by launchd, stderr goes nowhere and the unified log does
**not** capture its `NSLog`. Run the binary directly with stderr
redirected when you need to see them.

## Traps in the private API

- `DFRElementGetControlStripPresenceForIdentifier` **always returns 0**,
  even immediately after a successful set, in-process and cross-process.
  It is not a usable readback. The only way to know whether the item is
  really in the Control Strip is a screenshot.
- The Control Strip grants a **fixed ~64pt slot**. Widening the view's
  constraint does nothing (tested 132pt vs 220pt: identical). An icon
  fits; an app name does not. That is why the name gets a full-width
  flash instead.
- **Presenting or dismissing a system-modal touch bar tears our item out
  of the Control Strip.** Nothing reports this. Both the flash and the
  picker reinstall the tray item ~0.35s after dismissing.
- `ControlStrip.app` drops registrations when it restarts, and
  `NSWorkspaceDidLaunchApplicationNotification` is **not** posted for
  background agents like it. Its pid is polled instead.

## Accessibility is inherited, not granted

Window titles and raising windows need Accessibility. It cannot be granted
here (no screen), but macOS assigns it per *responsible process*:

- launched from a terminal that holds the grant (Alacritty does) →
  `AXIsProcessTrusted` is **YES**
- the same binary launched by launchd/LaunchServices → **NO**

`tools/ensure-ax-instance.sh`, called from `~/.zshrc`, swaps a non-trusted
instance for a trusted one. The LaunchAgent sets `KeepAlive false` so the
two do not fight. Check which mode is live:

```sh
defaults read com.tarik.touchbarstatus LastLaunchAXTrusted   # 1 full, 0 app-list-only
```

When a monitor is available, tick TouchBarStatus in System Settings →
Privacy & Security → Accessibility and the `~/.zshrc` line can go.

## Shell gotcha

Match the app process with `pgrep/pkill -fx "<full path>"`, never `-f`
with a substring. Any script whose *text* contains
`TouchBarStatus.app/Contents/MacOS` matches a loose `-f`, so a helper
once signalled its own shell and killed itself.

Also: macOS pids wrap past 99999. `pgrep ... | tail -1` is not "the
newest process". Compare against a known-before list instead.

## Apps are not one process each

Alacritty opens **one process per window**; Brave is one process with many
windows. `AppGroup` collapses both shapes into one picker entry. Alacritty
also reports an empty `AXWindows` array while clearly showing a window, so
`WindowList` falls back to `AXFocusedWindow`/`AXMainWindow` — without that
fallback every terminal session is invisible.

## Build

```sh
./build.sh      # universal x86_64 + arm64; most Touch Bar Macs are Intel
./install.sh    # build + ~/Applications + LaunchAgent
```

Repo: https://github.com/tarikee/touchbar-status
