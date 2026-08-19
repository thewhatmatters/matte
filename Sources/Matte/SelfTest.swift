import AppKit

/// `Matte --selftest` — assertions over the geometry that decides where
/// windows land. Runs without Accessibility permission.
enum SelfTest {
    private static var failures = 0
    private static var checks = 0

    // Studio Display: 2880x1620 at x=-2880, Dock reserving 54pt on the left and
    // a 30pt menu bar on top.
    private static let studioFrame = CGRect(x: -2880, y: 0, width: 2880, height: 1620)
    private static let studioVisible = CGRect(x: -2826, y: 0, width: 2826, height: 1590)

    static func run() -> Int32 {
        paddingIsMeasuredFromTheScreenEdge()
        fullWindowsTrackPaddingChanges()
        fullWindowsAreRecognisedAfterRelaunch()
        clampingKeepsWindowsInside()
        scopeSelectsTheRightWindows()
        coordinateFlipRoundTrips()

        print(failures == 0
              ? "PASS — \(checks) checks"
              : "FAIL — \(failures) of \(checks) checks failed")
        return failures == 0 ? 0 : 1
    }

    /// The Dock must not skew the numbers: 16pt means 16pt on all four edges.
    private static func paddingIsMeasuredFromTheScreenEdge() {
        let bounds = Geometry.contentBounds(frame: studioFrame, visibleFrame: studioVisible)
        expect(bounds == CGRect(x: -2880, y: 0, width: 2880, height: 1590),
               "content bounds span the whole screen width, minus only the menu bar")

        let even = padded(EdgePadding(top: 16, bottom: 16, left: 16, right: 16))
        expect(even == CGRect(x: -2864, y: 16, width: 2848, height: 1558),
               "16pt on every edge is 16pt from each physical screen edge")
        expect(even.minX - studioFrame.minX == 16, "left gap ignores the 54pt Dock reservation")
        expect(studioFrame.maxX - even.maxX == 16, "right gap matches the left gap exactly")
        expect(even.minY - studioFrame.minY == 16, "bottom gap matches too")
        expect(studioFrame.maxY - even.maxY == 16 + 30, "top gap is the padding plus the menu bar")

        // Clearing the Dock is then just a bigger number on that edge.
        let dockSide = padded(EdgePadding(top: 16, bottom: 16, left: 66, right: 16))
        expect(dockSide.minX == -2814, "a Dock-clearing gap sits past the 54pt the Dock occupies")
    }

    /// Changing the padding must resize full windows in *both* directions.
    private static func fullWindowsTrackPaddingChanges() {
        let bounds = Geometry.contentBounds(frame: studioFrame, visibleFrame: studioVisible)

        let maximized = studioVisible
        expect(Geometry.fillsScreen(maximized, bounds: bounds, visibleFrame: studioVisible),
               "a maximized window counts as filling the screen")

        // Shrinking: 0 -> 63pt of left padding.
        let wide = padded(EdgePadding(top: 0, bottom: 0, left: 63, right: 0))
        expect(wide.width == 2817 && wide.minX == -2817, "63pt left padding narrows the fill rect")

        // Growing back: 63pt -> 16pt. Clamping alone can only push inward, so
        // this is the case the filled-window tracking exists for.
        let narrow = padded(EdgePadding(top: 16, bottom: 16, left: 16, right: 16))
        expect(narrow.width > wide.width, "reducing the padding widens the target rect")
        let clampedOnly = Geometry.clamp(wide, into: narrow)
        expect(clampedOnly.width < narrow.width,
               "clamping alone never widens a window — tracking is what regrows it")
        expect(clampedOnly.width == wide.width,
               "clamping preserves the old, too-narrow width")

        // A window already at the padded rect keeps qualifying after a change.
        expect(Geometry.fillsScreen(wide, bounds: bounds, visibleFrame: studioVisible),
               "a window filling the padded area still reads as full")
    }

    /// After a relaunch the in-memory window map is gone, so recognition falls
    /// back to the rects the app recorded on disk.
    private static func fullWindowsAreRecognisedAfterRelaunch() {
        let bounds = Geometry.contentBounds(frame: studioFrame, visibleFrame: studioVisible)

        // Heavy padding shrinks a full window below the "looks full" threshold.
        let heavy = padded(EdgePadding(top: 200, bottom: 200, left: 200, right: 200))
        expect(!Geometry.fillsScreen(heavy, bounds: bounds, visibleFrame: studioVisible),
               "a heavily padded window no longer looks full on its own")
        expect(Geometry.matchesAppliedRect(heavy, history: [heavy]),
               "but it is recognised from the recorded rect")

        // A window the user sized themselves must not be swept up by it.
        let userSized = CGRect(x: -2000, y: 300, width: 900, height: 700)
        expect(!Geometry.matchesAppliedRect(userSized, history: [heavy, padded(EdgePadding())]),
               "an unrelated window does not match the history")

        // Recognition has to tolerate the point or two apps round to.
        let rounded = heavy.offsetBy(dx: 3, dy: -2)
        expect(Geometry.matchesAppliedRect(rounded, history: [heavy]),
               "a few points of app rounding still matches")
        expect(!Geometry.matchesAppliedRect(heavy.offsetBy(dx: 40, dy: 0), history: [heavy]),
               "a window nudged well off the rect does not match")
    }

    private static func clampingKeepsWindowsInside() {
        let target = padded(EdgePadding(top: 16, bottom: 16, left: 66, right: 16))

        let oversized = CGRect(x: -2900, y: -50, width: 3000, height: 1700)
        let fitted = Geometry.clamp(oversized, into: target)
        expect(fitted.width == target.width && fitted.height == target.height,
               "an oversized window shrinks to the padded size")
        expect(target.contains(fitted), "a clamped result is always inside the padded rect")

        let inside = CGRect(x: -2000, y: 400, width: 700, height: 500)
        expect(Geometry.clamp(inside, into: target) == inside,
               "a window already inside the padding is untouched")

        let absurd = Geometry.paddedRect(frame: studioFrame, visibleFrame: studioVisible,
                                         padding: EdgePadding(top: 900, bottom: 900, left: 1600, right: 1600))
        expect(absurd.width >= 200 && absurd.height >= 150, "absurd padding is floored to a usable size")
    }

    private static func scopeSelectsTheRightWindows() {
        let bounds = Geometry.contentBounds(frame: studioFrame, visibleFrame: studioVisible)

        let leftHalf = CGRect(x: -2826, y: 0, width: 1413, height: 1590)
        expect(Geometry.shouldClamp(leftHalf, bounds: bounds, scope: .largeWindows),
               "a half-screen snap qualifies via its height")

        let small = CGRect(x: -2000, y: 400, width: 700, height: 500)
        expect(!Geometry.shouldClamp(small, bounds: bounds, scope: .largeWindows),
               "a small window is left alone")
        expect(Geometry.shouldClamp(small, bounds: bounds, scope: .allWindows),
               "allWindows mode clamps everything")

        let offscreen = CGRect(x: -3200, y: 100, width: 1600, height: 1200)
        expect(!Geometry.shouldClamp(offscreen, bounds: bounds, scope: .largeWindows),
               "a window hanging off the edge is not yanked back")
    }

    private static func coordinateFlipRoundTrips() {
        let mainMaxY: CGFloat = 1169
        let appKit = CGRect(x: -2826, y: 0, width: 2826, height: 1620)
        let ax = Geometry.flip(appKit, mainScreenMaxY: mainMaxY)
        expect(ax.origin.y == 1169 - 1620, "a screen taller than the main display gets a negative AX y")
        expect(Geometry.flip(ax, mainScreenMaxY: mainMaxY) == appKit, "the flip round-trips")

        // Built-in display with the Dock on the bottom.
        let builtInFrame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let builtInVisible = CGRect(x: 0, y: 70, width: 1800, height: 1060)
        let rect = Geometry.paddedRect(frame: builtInFrame, visibleFrame: builtInVisible,
                                       padding: EdgePadding(top: 0, bottom: 90, left: 0, right: 0))
        expect(rect == CGRect(x: 0, y: 90, width: 1800, height: 1040),
               "bottom padding is measured from the screen edge, not from above the Dock")
    }

    private static func padded(_ padding: EdgePadding) -> CGRect {
        Geometry.paddedRect(frame: studioFrame, visibleFrame: studioVisible, padding: padding)
    }

    private static func expect(_ condition: Bool, _ description: String) {
        checks += 1
        if !condition {
            failures += 1
            print("  ✗ \(description)")
        }
    }
}
