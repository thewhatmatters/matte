import AppKit

/// The running menu bar app publishes its own state to disk.
///
/// `AXIsProcessTrusted()` reports the *calling* process's permission, and a
/// terminal-launched copy of this binary is attributed to the terminal — so
/// asking the binary directly gives a misleading answer. `--status` reads this
/// file instead, which is written by the process that actually holds the grant.
enum StatusFile {
    struct Snapshot: Codable {
        var writtenAt: Date
        var pid: Int32
        var trusted: Bool
        var enabled: Bool
        var windowScope: String
        var launchAtLogin: Bool
        var displays: [Display]
        var windowsOutsidePadding: [String]

        struct Display: Codable {
            var name: String
            var visibleFrame: [Double]
            var paddedRect: [Double]
            var padding: EdgePadding
            var isCustom: Bool
        }
    }

    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Matte", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    private static var timer: Timer?

    static func startPublishing() {
        write()
        // 5s keeps the extra window enumeration well clear of the 2s sweep.
        let timer = Timer(timeInterval: 5, repeats: true) { _ in write() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func write() {
        let settings = Settings.shared
        let trusted = AX.isTrusted
        let displays = PaddingEngine.shared.paddedRects().map { entry in
            Snapshot.Display(
                name: entry.screen.localizedName,
                visibleFrame: entry.screen.visibleFrame.asArray,
                paddedRect: entry.rect.asArray,
                padding: settings.padding(for: entry.screen),
                isCustom: settings.hasOverride(entry.screen)
            )
        }
        let snapshot = Snapshot(
            writtenAt: Date(),
            pid: ProcessInfo.processInfo.processIdentifier,
            trusted: trusted,
            enabled: settings.isEnabled,
            windowScope: settings.windowScope.rawValue,
            launchAtLogin: LoginItem.isEnabled,
            displays: displays,
            windowsOutsidePadding: trusted ? PaddingEngine.shared.diagnosticOverflowReport() : []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}

private extension CGRect {
    var asArray: [Double] { [origin.x, origin.y, width, height] }
}
