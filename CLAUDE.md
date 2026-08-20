# Matte

A macOS menu bar app that reserves padding around the edges of each display, so
maximized windows stop covering the Dock. Per-edge, per-display, adjustable live
from a popover. There is no public API to reserve desktop space, so the app
resizes other apps' windows through the Accessibility API — the same approach
Rectangle and Loop use.

## Tech stack

- Swift 6 / SwiftPM executable target, no third-party dependencies.
- AppKit for the status item, popover, and overlay; SwiftUI for the popover content.
- `ApplicationServices` (AXUIElement / AXObserver) for window control.
- Ships as a hand-assembled `.app` bundle — there is no Xcode project.

## Architecture

| Path | Responsibility |
|---|---|
| `Sources/Matte/Geometry.swift` | All padding, clamping, and coordinate math. Pure — no AppKit state. |
| `Sources/Matte/PaddingEngine.swift` | AX observers, periodic sweep, window adjustment, filled-window tracking. |
| `Sources/Matte/AX.swift` | Accessibility wrapper and the AX↔AppKit coordinate flip. |
| `Sources/Matte/Settings.swift` | Per-display padding model, applied-rect history, persistence. |
| `Sources/Matte/SettingsView.swift` | The panel UI. |
| `Sources/Matte/Theme.swift` | Design tokens taken from the Paper file. |
| `Sources/Matte/PanelWindow.swift` | Borderless NSPanel container, positioning, dismissal. |
| `Sources/Matte/PanelControls.swift` | Hand-built slider, fields, buttons, toggles. |
| `Sources/Matte/DisplayStrip.swift` | Display tiles with wallpaper thumbnails. |
| `Sources/Matte/StatusFile.swift` | Publishes live state to disk for `--status`. |
| `Sources/Matte/SelfTest.swift` | Geometry assertions run by `--selftest`. |
| `build.sh` | Build → assemble bundle → sign → optionally install. |

## Rules

**Keep geometry pure.** Padding, clamping, fill-detection, and the coordinate
flip live in `Geometry.swift` as static functions over plain `CGRect`s. The
engine reads `NSScreen` and calls into them. This is what lets `--selftest`
verify the math with no Accessibility grant and no GUI — protect it.

**Every geometry change gets a `SelfTest.swift` assertion.** Name the behaviour,
not the implementation (`fullWindowsTrackPaddingChanges`, not `testClamp2`).

**Measure padding from `screen.frame`, never `visibleFrame`.** 16pt must read as
16pt on all four edges regardless of what the Dock reserves. The menu bar is the
single exception carved out, in `Geometry.contentBounds`.

**Convert coordinates through `Geometry.flip` / `Coordinates`.** Accessibility is
top-left origin (+Y down) anchored to the main display; AppKit is bottom-left
(+Y up). Never hand-roll the flip at a call site.

**Guard every AX write with `isAdjusting`** and bound AX reads with a messaging
timeout — an unresponsive app must not stall the main-thread sweep.

**Run `--selftest` and `--uicheck` before reporting a change as done.** Both are
headless and take under a second.

**Review UI changes with `--render`.** It writes the panel to PNGs via
`ImageRenderer`, which is the only way to see the panel without opening it.
`ImageRenderer` cannot draw AppKit-backed views, so `TextField`s appear as
yellow placeholders — that is a render artifact, not a layout bug.

## Commands

```bash
./build.sh                  # build + bundle into ./build
./build.sh --install        # also sign, install to /Applications, launch
./build.sh --release        # notarize, staple, and emit a shippable zip

.build/release/Matte --selftest    # geometry assertions
.build/release/Matte --uicheck     # panel layout, all four expand states
.build/release/Matte --render DIR  # render the panel to PNGs to review visually
.build/release/Matte --flash      # show the padding outline for 3s on every display

# Against the installed app:
"/Applications/Matte.app/Contents/MacOS/Matte" --status
"/Applications/Matte.app/Contents/MacOS/Matte" --set-padding 24
```

## Interaction

Left-click the status item opens the panel; right-click opens a menu with the
enable toggle, Apply Now and Quit. The panel's footer is Settings and Apply
only — the design has no Quit, so the menu is the only way to exit.

## Gotchas

**Run the CLI flags from the app bundle, not `.build/release`.** A bare
executable has no `Bundle.main.bundleIdentifier`, so `UserDefaults.standard`
resolves to a different domain and `--render`, `--status` and `--set-padding`
silently operate on empty settings. Use
`./build/Matte.app/Contents/MacOS/Matte` or the installed copy.

**`--status` reads a published state file, not its own permission.** A
terminal-launched copy of the binary is attributed to the *terminal* by TCC, so
calling `AXIsProcessTrusted()` there reports the terminal's grant and lies about
the app's. `StatusFile` exists for exactly this reason. Never verify the
Accessibility grant by running the binary directly.

**Notarization is required before the app leaves this machine as a file.**
Gatekeeper blocks an un-notarized app arriving via download, AirDrop or cloud
sync. Building from source on the target Mac is never quarantined, which is why
this is invisible until someone is handed a binary. `./build.sh --release`
submits, staples and verifies; credentials live in a keychain profile, never in
the repo.

**Sign with a real identity, not ad-hoc.** TCC keys an ad-hoc signature to the
binary hash, so every rebuild silently invalidates the Accessibility grant while
leaving the System Settings toggle switched *on* — indistinguishable from an app
bug. `build.sh` picks Developer ID → Apple Development → ad-hoc, and only clears
the stale TCC entry when it had to fall back to ad-hoc.

**Verify window geometry with `CGWindowListCopyWindowInfo`.** Window *bounds*
need no permission, so it measures the app's real effect from outside. Do not
try to screenshot for verification — Screen Recording is typically not granted
to the terminal and `screencapture` fails outright.

**Clamping can only push a window inward.** Growing a window when the padding
shrinks requires the filled-window tracking in `PaddingEngine` plus the applied
-rect history in `Settings`. Window identity cannot survive a process restart,
which is why the history is persisted rather than the window references.

**Accessibility notifications are unreliable in some apps.** The 2s sweep is the
safety net, not redundancy. It is skipped while a mouse button is down so a drag
is never interrupted.

<!-- wire-vault:start -->
## Knowledge vault — project layer

This project's durable knowledge (overview, decisions, gotchas) lives in the
cross-project vault at `<vault>/projects/display-padding/`
(default vault: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/OBSDN`).

- **Read first:** before re-deriving an architecture decision or re-debugging
  a non-obvious issue, check `projects/display-padding/index.md` there.
- **Write path:** durable insights go through `/curate-vault` (gated) —
  never write vault articles directly.
<!-- wire-vault:end -->
