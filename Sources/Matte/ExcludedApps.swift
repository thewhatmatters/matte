import AppKit
import SwiftUI

/// Apps Matte leaves alone. The escape hatch for anything that fights back —
/// notably apps enforcing a minimum window size larger than the padded area,
/// which can never fit however many times they are asked.
enum ExcludedApps {
    /// Display name for a bundle identifier, whether or not it is running.
    static func name(for bundleID: String) -> String {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// Running apps that could be excluded, minus the ones already excluded.
    static func candidates(excluding excluded: [String]) -> [(id: String, name: String)] {
        let taken = Set(excluded)
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, id != own, !taken.contains(id),
                      let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}

/// The excluded-apps row in Settings: a header with an add menu, then one row
/// per excluded app.
struct ExcludedAppsSection: View {
    private let theme = Theme.current
    @Binding var excluded: [String]
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Never resize")
                    .font(theme.font(12.5))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                Menu {
                    let options = ExcludedApps.candidates(excluding: excluded)
                    if options.isEmpty {
                        Text("No other apps running")
                    } else {
                        ForEach(options, id: \.id) { option in
                            Button(option.name) {
                                excluded.append(option.id)
                                onChange()
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .help("Leave an app's windows alone")
            }

            ForEach(excluded, id: \.self) { bundleID in
                HStack(spacing: 6) {
                    Text(ExcludedApps.name(for: bundleID))
                        .font(theme.font(12.5))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        excluded.removeAll { $0 == bundleID }
                        onChange()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Resize \(ExcludedApps.name(for: bundleID)) again")
                }
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}
