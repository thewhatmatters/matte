import AppKit
import ApplicationServices

/// Watches every running app's windows and keeps them inside a padded region of
/// each screen, so the Dock (and any other desktop edge) stays uncovered.
final class PaddingEngine {
    static let shared = PaddingEngine()

    private let settings = Settings.shared
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: [pid_t: Set<WindowKey>] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]
    private var sweepTimer: Timer?
    private var trustPollTimer: Timer?
    private var pendingRecheck: DispatchWorkItem?
    private var isAdjusting = false

    /// Windows we resized ourselves and that refused to shrink; retrying every
    /// sweep would just thrash them.
    private var stubbornWindows = Set<WindowKey>()

    /// Windows given a second attempt already. Some apps re-assert their own
    /// size just after we set one, so a single delayed retry wins where an
    /// immediate one can't — but only ever one, or it becomes a tug of war.
    private var retriedWindows = Set<WindowKey>()

    /// Windows currently filling the padded area, and the frame we last gave
    /// them. This is what lets a full window *grow* when the padding shrinks —
    /// clamping alone can only ever push inward.
    private var filledWindows: [WindowKey: CGRect] = [:]

    /// Frames captured before the last "fill windows" run, so it can be undone.
    /// Window references can't outlive the process, which is fine — undo is only
    /// ever offered for the run that just happened.
    private var fillUndoStack: [(window: AXUIElement, frame: CGRect)] = []

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        attachToRunningApps()
        restartSweepTimer()
        applyToAllWindows()
        startTrustPollingIfNeeded()
    }

    /// The Accessibility grant can land while the popover is closed, so the
    /// engine watches for it itself rather than relying on the UI.
    private func startTrustPollingIfNeeded() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
        guard !AX.isTrusted else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            guard AX.isTrusted else { return }
            timer.invalidate()
            self?.trustPollTimer = nil
            self?.retryAfterPermissionGranted()
        }
        RunLoop.main.add(timer, forMode: .common)
        trustPollTimer = timer
    }

    func settingsChanged() {
        stubbornWindows.removeAll()
        retriedWindows.removeAll()
        fillUndoStack.removeAll()
        restartSweepTimer()
        applyToAllWindows()
    }

    private func restartSweepTimer() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        guard settings.isEnabled else { return }
        // Not every app emits reliable AX notifications; a light sweep keeps the
        // padding honest without fighting the user mid-drag.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.settings.windowScope == .largeWindows else { return }
            guard !Self.mouseButtonIsDown else { return }
            self.applyToAllWindows()
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    // MARK: - Geometry

    private func paddedRect(for screen: NSScreen) -> CGRect {
        Geometry.paddedRect(frame: screen.frame, visibleFrame: screen.visibleFrame,
                            padding: settings.padding(for: screen))
    }

    /// Every padded rect this app has applied, on any display — a window that
    /// still matches one was sized by us, even if it has since been dragged to
    /// a different screen.
    private var recordedRectsAcrossScreens: [CGRect] {
        targetScreens.flatMap { settings.appliedRects(for: $0) }
    }

    private func contentBounds(for screen: NSScreen) -> CGRect {
        Geometry.contentBounds(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    private var targetScreens: [NSScreen] { NSScreen.screens }

    func paddedRects() -> [(screen: NSScreen, rect: CGRect)] {
        targetScreens.map { ($0, paddedRect(for: $0)) }
    }

    private func screen(for appKitRect: CGRect) -> NSScreen? {
        targetScreens.max { a, b in
            a.frame.intersection(appKitRect).area < b.frame.intersection(appKitRect).area
        }.flatMap { $0.frame.intersects(appKitRect) ? $0 : nil }
    }

    // MARK: - Applying

    func applyToAllWindows() {
        guard settings.isEnabled, AX.isTrusted else { return }
        for screen in targetScreens where settings.hasAnyPadding {
            settings.recordAppliedRect(paddedRect(for: screen), for: screen)
        }
        var live = Set<WindowKey>()
        for app in Self.managedApps() {
            live.formUnion(apply(toApp: app.processIdentifier))
        }
        // Closed windows would otherwise accumulate in both caches forever.
        filledWindows = filledWindows.filter { live.contains($0.key) }
        stubbornWindows.formIntersection(live)
        retriedWindows.formIntersection(live)
    }

    /// Cached per-process element with a short messaging timeout — a hung app
    /// must not stall the sweep on the main thread.
    private func appElement(for pid: pid_t) -> AXUIElement {
        if let cached = appElements[pid] { return cached }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        appElements[pid] = element
        return element
    }

    @discardableResult
    private func apply(toApp pid: pid_t) -> Set<WindowKey> {
        guard settings.isEnabled, AX.isTrusted else { return [] }
        var seen = Set<WindowKey>()
        for window in AX.elements(appElement(for: pid), kAXWindowsAttribute) {
            seen.insert(WindowKey(window))
            observeWindow(window, pid: pid)
            adjust(window: window, pid: pid)
        }
        return seen
    }

    @discardableResult
    private func adjust(window: AXUIElement, pid: pid_t) -> Bool {
        guard settings.isEnabled, settings.hasAnyPadding else { return false }
        guard !isAdjusting else { return false }
        guard isManageable(window: window) else { return false }
        guard let axRect = AX.frame(window) else { return false }

        let current = Coordinates.toAppKit(axRect)
        guard let screen = screen(for: current) else { return false }
        let padded = paddedRect(for: screen)
        let bounds = contentBounds(for: screen)
        let key = WindowKey(window)

        // A window that was filling the padded area keeps filling it when the
        // padding changes, in either direction.
        if let applied = filledWindows[key] {
            if current.approximatelyEquals(applied, tolerance: 6) {
                guard !current.approximatelyEquals(padded),
                      !stubbornWindows.contains(key) else { return false }
                return fill(window: window, to: padded, key: key)
            }
            // Dragged to another display at the same size: still a filled
            // window, just one that now belongs to a different screen.
            let previous = self.screen(for: applied).map(Settings.key(for:))
            if Geometry.keptItsSize(current, wasAt: applied),
               previous != Settings.key(for: screen) {
                return fill(window: window, to: padded, key: key)
            }
            // Otherwise the user resized it themselves, so stop tracking it.
            filledWindows.removeValue(forKey: key)
        }

        // Either it looks full right now, or it is parked on a rect we applied
        // before the last relaunch.
        // Either it looks full on this screen, or it still carries a size this
        // app gave it on some screen — the latter catches a window dragged
        // across displays, whose position tells us nothing.
        if Geometry.fillsScreen(current, bounds: bounds, visibleFrame: screen.visibleFrame)
            || Geometry.matchesAppliedRect(current, history: recordedRectsAcrossScreens)
            || Geometry.matchesAppliedSize(current, history: recordedRectsAcrossScreens) {
            guard !current.approximatelyEquals(padded) else {
                filledWindows[key] = current
                return false
            }
            return fill(window: window, to: padded, key: key)
        }

        guard !padded.contains(roundedForCompare(current)) else { return false }
        guard shouldClamp(current, bounds: bounds) else { return false }

        let target = clamp(current, into: padded)
        guard !target.approximatelyEquals(current) else { return false }

        if stubbornWindows.contains(key) { return false }

        isAdjusting = true
        AX.setFrame(window, Coordinates.toAccessibility(target))
        isAdjusting = false

        // Some apps enforce a minimum size. If the result still overflows, nudge
        // it back inside as far as it will go and stop retrying it every sweep.
        if let resultAX = AX.frame(window) {
            let result = Coordinates.toAppKit(resultAX)
            if !padded.contains(roundedForCompare(result)) {
                let retry = clamp(result, into: padded)
                if !retry.approximatelyEquals(result) {
                    isAdjusting = true
                    AX.setFrame(window, Coordinates.toAccessibility(CGRect(origin: retry.origin, size: result.size)))
                    isAdjusting = false
                }
                if let finalAX = AX.frame(window),
                   !padded.contains(roundedForCompare(Coordinates.toAppKit(finalAX))) {
                    stubbornWindows.insert(key)
                }
            }
        }
        return true
    }

    /// Resizes a filling window to exactly the padded rect and remembers the
    /// result, so the next padding change can move it again.
    @discardableResult
    private func fill(window: AXUIElement, to padded: CGRect, key: WindowKey) -> Bool {
        isAdjusting = true
        AX.setFrame(window, Coordinates.toAccessibility(padded))
        isAdjusting = false
        let achieved = AX.frame(window).map(Coordinates.toAppKit) ?? padded
        filledWindows[key] = achieved
        // Some apps refuse the exact rect — Electron ones commonly land a few
        // points off. Without this the next sweep sees a mismatch and asks
        // again, every two seconds, forever.
        if !achieved.approximatelyEquals(padded, tolerance: 6) {
            scheduleFillRetry(window: window, padded: padded, key: key)
        }
        if let screen = screen(for: achieved) {
            settings.recordAppliedRect(achieved, for: screen)
        }
        return true
    }

    private func shouldClamp(_ rect: CGRect, bounds: CGRect) -> Bool {
        Geometry.shouldClamp(rect, bounds: bounds, scope: settings.windowScope)
    }

    private func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        Geometry.clamp(rect, into: bounds)
    }

    private func roundedForCompare(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: 1, dy: 1)
    }

    private func isManageable(window: AXUIElement) -> Bool {
        if AX.bool(window, kAXMinimizedAttribute) { return false }
        if AX.bool(window, "AXFullScreen") { return false }
        if let subrole = AX.string(window, kAXSubroleAttribute), subrole != kAXStandardWindowSubrole {
            return false
        }
        return true
    }

    // MARK: - Filling

    var canUndoFill: Bool { !fillUndoStack.isEmpty }

    /// Sizes every eligible window on one screen to its padded rect.
    @discardableResult
    func fillWindows(on screen: NSScreen) -> Int {
        guard AX.isTrusted, settings.isEnabled else { return 0 }
        let padded = paddedRect(for: screen)
        var snapshot: [(window: AXUIElement, frame: CGRect)] = []

        for app in Self.managedApps() {
            let pid = app.processIdentifier
            for window in AX.elements(appElement(for: pid), kAXWindowsAttribute) {
                guard isManageable(window: window), let axRect = AX.frame(window) else { continue }
                let current = Coordinates.toAppKit(axRect)
                guard let host = self.screen(for: current),
                      Settings.key(for: host) == Settings.key(for: screen),
                      !current.approximatelyEquals(padded) else { continue }
                snapshot.append((window, current))
                observeWindow(window, pid: pid)
                fill(window: window, to: padded, key: WindowKey(window))
            }
        }
        if !snapshot.isEmpty { fillUndoStack = snapshot }
        return snapshot.count
    }

    func undoFill() {
        let restore = fillUndoStack
        fillUndoStack = []
        isAdjusting = true
        for entry in restore {
            AX.setFrame(entry.window, Coordinates.toAccessibility(entry.frame))
            filledWindows.removeValue(forKey: WindowKey(entry.window))
        }
        isAdjusting = false
    }

    func discardFillUndo() { fillUndoStack = [] }

    private func scheduleFillRetry(window: AXUIElement, padded: CGRect, key: WindowKey) {
        guard !retriedWindows.contains(key) else {
            stubbornWindows.insert(key)
            return
        }
        retriedWindows.insert(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.settings.isEnabled, !self.isAdjusting else { return }
            self.isAdjusting = true
            AX.setFrame(window, Coordinates.toAccessibility(padded))
            self.isAdjusting = false
            let settled = AX.frame(window).map(Coordinates.toAppKit) ?? padded
            self.filledWindows[key] = settled
            if !settled.approximatelyEquals(padded, tolerance: 6) {
                self.stubbornWindows.insert(key)
            }
        }
    }

    /// Opt-in: size a freshly created window to the padded area. Windows that
    /// open small are left alone — dialogs and palettes report as standard
    /// windows too, and forcing those full is worse than doing nothing.
    private func fillIfEligible(window: AXUIElement) {
        guard settings.isEnabled, settings.fillNewWindows, AX.isTrusted else { return }
        guard isManageable(window: window), let axRect = AX.frame(window) else { return }
        let current = Coordinates.toAppKit(axRect)
        guard let screen = screen(for: current) else { return }
        let bounds = contentBounds(for: screen)
        guard current.width >= bounds.width * 0.28,
              current.height >= bounds.height * 0.28 else { return }
        let padded = paddedRect(for: screen)
        guard !current.approximatelyEquals(padded) else { return }
        fill(window: window, to: padded, key: WindowKey(window))
    }

    // MARK: - Observation

    private static func managedApps() -> [NSRunningApplication] {
        let excluded = Set(Settings.shared.excludedBundleIDs)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !app.isTerminated
                && !(app.bundleIdentifier.map(excluded.contains) ?? false)
        }
    }

    private func attachToRunningApps() {
        for app in Self.managedApps() {
            attach(to: app.processIdentifier)
        }
    }

    private func attach(to pid: pid_t) {
        guard AX.isTrusted, observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let engine = Unmanaged<PaddingEngine>.fromOpaque(refcon).takeUnretainedValue()
            engine.handle(notification: notification as String, element: element)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = self.appElement(for: pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification,
                     kAXFocusedWindowChangedNotification,
                     kAXApplicationActivatedNotification,
                     kAXWindowMovedNotification,
                     kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, appElement, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        apply(toApp: pid)
    }

    /// Per-window move/resize notifications: registering on the app element only
    /// works for some apps, so windows are registered individually as they appear.
    private func observeWindow(_ window: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        let key = WindowKey(window)
        if observedWindows[pid]?.contains(key) == true { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, window, name as CFString, context)
        }
        observedWindows[pid, default: []].insert(key)
    }

    private func detach(from pid: pid_t) {
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers[pid] = nil
        observedWindows[pid] = nil
        appElements[pid] = nil
    }

    private func handle(notification: String, element: AXUIElement) {
        guard settings.isEnabled, !isAdjusting else { return }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        switch notification {
        case kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXApplicationActivatedNotification:
            scheduleRecheck(after: 0.05) { [weak self] in self?.apply(toApp: pid) }
            if notification == kAXWindowCreatedNotification, settings.fillNewWindows {
                // Apps commonly set their own size just after creating a window;
                // let that settle first so we aren't immediately overridden.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.fillIfEligible(window: element)
                }
            }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if Self.mouseButtonIsDown {
                // Wait for the drag to finish rather than yanking the window
                // out from under the cursor.
                scheduleRecheck(after: 0.25) { [weak self] in
                    guard let self else { return }
                    if Self.mouseButtonIsDown {
                        self.handle(notification: notification, element: element)
                    } else {
                        self.adjust(window: element, pid: pid)
                    }
                }
            } else {
                adjust(window: element, pid: pid)
            }
        default:
            break
        }
    }

    private func scheduleRecheck(after delay: TimeInterval, _ block: @escaping () -> Void) {
        pendingRecheck?.cancel()
        let item = DispatchWorkItem(block: block)
        pendingRecheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private static var mouseButtonIsDown: Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    // MARK: - Workspace events

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        // Apps need a moment before their AX tree is answering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.attach(to: app.processIdentifier)
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        detach(from: app.processIdentifier)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(to: app.processIdentifier)
        apply(toApp: app.processIdentifier)
    }

    @objc private func screensChanged() {
        stubbornWindows.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyToAllWindows()
        }
    }

    /// Human-readable list of windows that currently sit outside the padded
    /// area. Read-only — used by `--status`.
    func diagnosticOverflowReport() -> [String] {
        var report: [String] = []
        for app in Self.managedApps() {
            for window in AX.elements(appElement(for: app.processIdentifier), kAXWindowsAttribute) {
                guard isManageable(window: window), let axRect = AX.frame(window) else { continue }
                let rect = Coordinates.toAppKit(axRect)
                guard let screen = screen(for: rect) else { continue }
                let padded = paddedRect(for: screen)
                if !padded.contains(roundedForCompare(rect)) {
                    let name = app.localizedName ?? "?"
                    let title = AX.string(window, kAXTitleAttribute) ?? ""
                    report.append("\(name) — \(title.isEmpty ? "untitled" : title) @ \(rect.integral)")
                }
            }
        }
        return report
    }

    /// Re-attach after Accessibility permission is granted without a relaunch.
    func retryAfterPermissionGranted() {
        guard AX.isTrusted else { return }
        attachToRunningApps()
        applyToAllWindows()
    }
}

// MARK: - Helpers

/// AXUIElement is a CFType; this makes it usable as a dictionary/set key.
struct WindowKey: Hashable {
    private let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
