import AppKit

/// Notices when a newer release is published on GitHub.
///
/// No framework and no hosting: publishing a release tag is the entire deploy
/// step, and the API is readable without a token because the repository is
/// public. It only ever *tells* you an update exists — installing is still a
/// download, which is the trade for not embedding an updater.
@MainActor
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    private static let endpoint = URL(
        string: "https://api.github.com/repos/thewhatmatters/matte/releases/latest")!
    private static let interval: TimeInterval = 60 * 60 * 24

    @Published private(set) var availableVersion: String?
    private(set) var releaseURL: URL?
    private var timer: Timer?

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start() {
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in UpdateCheck.shared.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            Task { @MainActor in UpdateCheck.shared.apply(tag: tag, page: page) }
        }.resume()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releaseURL
            ?? URL(string: "https://github.com/thewhatmatters/matte/releases/latest")!)
    }

    private func apply(tag: String, page: URL?) {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(latest, than: currentVersion) else {
            availableVersion = nil
            return
        }
        availableVersion = latest
        releaseURL = page
    }

    /// Component-wise numeric compare, so 1.10 beats 1.9 — a string compare
    /// would get that backwards.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
