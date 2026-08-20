# Matte

A macOS menu bar app that reserves padding around the edges of your desktop, so
maximized windows stop covering the Dock (or any edge you want kept clear).

macOS only reserves space for the Dock when it's pinned, and even then windows
sit flush against it. Matte lets you define a per-edge, per-display
margin and keeps windows inside it.

## Build & install

```bash
./build.sh --install     # build, copy to /Applications, launch
./build.sh               # build only, into ./build
```

On first launch macOS asks for **Accessibility** access — the app resizes other
apps' windows, which is gated behind that permission.

> System Settings → Privacy & Security → Accessibility → enable **Matte**

The app picks up the grant within a second or two; no relaunch needed.

## Using it

Click the menu bar icon for the popover. Right-click it to toggle padding on/off.

| Control | What it does |
| --- | --- |
| **Editing** | Choose "All displays" (the default values) or a single display to give it its own padding |
| **Top / Bottom / Left / Right** | Points of margin reserved on each edge |
| **Link all edges** | Move one slider, move them all |
| **Match my Dock** | Adds a gap on the Dock's edge, on the display the Dock is actually on |
| **Affects** | *Large windows* (maximized and half-screen snaps) or *All windows* |
| **Apply Now** | Re-checks every window immediately |

The padding is measured from each screen's `visibleFrame`, so it stacks on top
of the space macOS already reserves for the menu bar and a pinned Dock.

On first run the app reads your Dock's position, size, and which display it's on,
and seeds the padding there.

## Behaviour notes

- **Large windows** mode only touches windows that fill or half-fill a screen and
  are parked on-screen. A window you deliberately dragged past an edge is left alone.
- Native full-screen windows and minimized windows are never touched.
- Windows are re-checked on move, resize, creation, and app activation, plus a
  light sweep every 2s for apps that don't emit Accessibility notifications.
- While the mouse button is down the app waits, so it never yanks a window out
  from under the cursor mid-drag.
- Apps that refuse to shrink below a minimum size get repositioned as far inside
  the padding as they'll go, then skipped on later sweeps instead of thrashing.

## Command line

```bash
"/Applications/Matte.app/Contents/MacOS/Matte" --status
"/Applications/Matte.app/Contents/MacOS/Matte" --selftest
```

`--status` reports permission state, Dock config, and each display's padded rect,
plus any windows currently outside it. `--selftest` runs the geometry assertions.

## Layout

| File | Role |
| --- | --- |
| `Geometry.swift` | Pure padding/clamping math (covered by `--selftest`) |
| `PaddingEngine.swift` | Accessibility observers, sweeps, window adjustment |
| `AX.swift` | Accessibility wrapper and the AX↔AppKit coordinate flip |
| `Settings.swift` | Persisted per-display padding model |
| `SettingsView.swift` | The popover UI |
| `OverlayController.swift` | The outline shown while adjusting |
| `DockInfo.swift` | Reads `com.apple.dock` for sensible defaults |

## Caveats

- The bundle is **ad-hoc signed**. Rebuilding changes the signature, so macOS may
  ask for Accessibility access again — re-toggle it in System Settings if the
  padding stops applying after a rebuild.
- Some apps (notably ones with hard minimum window sizes, and Electron apps that
  manage their own geometry) may resist. Use *Apply Now*, or leave them out via
  the `excludedBundleIDs` preference.

## License

MIT — see [LICENSE](LICENSE).
