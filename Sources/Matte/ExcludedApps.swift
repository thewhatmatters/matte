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

    /// Running apps that could appear in the picker, including ones already excluded.
    static func running() -> [(id: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted,
                      let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    static func filtered(query: String) -> [(id: String, name: String)] {
        let all = running()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }
}

/// Field bounds so the list can overlay the panel instead of stretching it.
struct ComboboxAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Combobox field: chips plus a search input. The list is drawn by the panel
/// overlay so it can sit on top of the footer without resizing the window.
struct ExcludedAppsSection: View {
    private let theme = Theme.current
    @ObservedObject private var metrics = PanelMetrics.shared
    @Binding var excluded: [String]
    @Binding var query: String
    @Binding var highlighted: String?
    let onChange: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Never resize")
                .font(theme.font(12.5))
                .foregroundStyle(theme.textSecondary)

            field
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .onChange(of: metrics.comboboxOpen) { _, open in
            if !open { fieldFocused = false }
        }
        .onChange(of: ExcludedApps.filtered(query: query).map(\.id)) { _, ids in
            if let highlighted, ids.contains(highlighted) { return }
            highlighted = ids.first
        }
    }

    private var field: some View {
        HStack(spacing: 4) {
            ChipFlow(spacing: 6, lineSpacing: 6) {
                ForEach(excluded, id: \.self) { bundleID in
                    chip(bundleID)
                }
                TextField(excluded.isEmpty ? "Search running apps" : "", text: $query)
                    .textFieldStyle(.plain)
                    .font(theme.font(13))
                    .foregroundStyle(theme.textPrimary)
                    .focused($fieldFocused)
                    .frame(minWidth: 72, minHeight: 22)
                    .onSubmit { toggleHighlighted() }
                    .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
                    .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
                    .onKeyPress(.escape) {
                        if metrics.comboboxOpen {
                            metrics.comboboxOpen = false
                            return .handled
                        }
                        return .ignored
                    }
                    .accessibilityLabel("Apps Matte should never resize")
            }

            Button {
                metrics.comboboxOpen.toggle()
                fieldFocused = metrics.comboboxOpen
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .rotationEffect(.degrees(metrics.comboboxOpen ? 180 : 0))
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 22)
            .help(metrics.comboboxOpen ? "Close the list" : "Choose apps to leave alone")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(minHeight: theme.fieldHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.fieldRadius).fill(theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: theme.fieldRadius)
            .stroke(theme.fieldBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: theme.fieldRadius))
        .anchorPreference(key: ComboboxAnchorKey.self, value: .bounds) { $0 }
        .simultaneousGesture(TapGesture().onEnded {
            metrics.comboboxOpen = true
            fieldFocused = true
        })
        .onChange(of: fieldFocused) { _, focused in
            if focused { metrics.comboboxOpen = true }
        }
        .onChange(of: query) { _, value in
            if !value.isEmpty { metrics.comboboxOpen = true }
        }
    }

    private func chip(_ bundleID: String) -> some View {
        let name = ExcludedApps.name(for: bundleID)
        return HStack(spacing: 4) {
            Text(name)
                .font(theme.font(12.5))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Button {
                excluded.removeAll { $0 == bundleID }
                onChange()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Resize \(name) again")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.08)))
    }

    private func toggleHighlighted() {
        let options = ExcludedApps.filtered(query: query)
        let id = highlighted ?? options.first?.id
        guard let id else { return }
        ExcludedAppsMenu.toggle(id, in: &excluded)
        onChange()
    }

    private func moveHighlight(_ step: Int) {
        metrics.comboboxOpen = true
        let ids = ExcludedApps.filtered(query: query).map(\.id)
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : 0)
        let next = (current + step + ids.count) % ids.count
        highlighted = ids[next]
    }
}

/// The floating list. Drawn over the panel so opening it does not change height.
struct ExcludedAppsMenu: View {
    private let theme = Theme.current
    @Binding var excluded: [String]
    @Binding var query: String
    @Binding var highlighted: String?
    let onChange: () -> Void

    var body: some View {
        let options = ExcludedApps.filtered(query: query)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if options.isEmpty {
                    Text(query.isEmpty ? "No other apps running" : "No matching apps")
                        .font(theme.font(12.5))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(options, id: \.id) { option in
                        row(option)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: theme.fieldRadius).fill(theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: theme.fieldRadius)
            .stroke(theme.fieldBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }

    private func row(_ option: (id: String, name: String)) -> some View {
        let selected = excluded.contains(option.id)
        let active = highlighted == option.id
        return Button {
            Self.toggle(option.id, in: &excluded)
            onChange()
        } label: {
            HStack(spacing: 8) {
                Text(option.name)
                    .font(theme.font(13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { highlighted = option.id }
        }
    }

    static func toggle(_ id: String, in excluded: inout [String]) {
        if let index = excluded.firstIndex(of: id) {
            excluded.remove(at: index)
        } else {
            excluded.append(id)
        }
    }
}

/// Wraps chips onto new lines and lets the trailing search field fill what's left.
private struct ChipFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
                             subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified)
            let isField = index == subviews.count - 1
            if isField {
                if x > 0 && maxWidth.isFinite && maxWidth - x < 64 {
                    y += rowHeight + lineSpacing
                    x = 0
                    rowHeight = 0
                }
                let width = maxWidth.isFinite ? max(64, maxWidth - x) : max(natural.width, 64)
                let height = max(natural.height, 22)
                frames.append(CGRect(x: x, y: y, width: width, height: height))
                x += width
                rowHeight = max(rowHeight, height)
            } else {
                if x > 0 && maxWidth.isFinite && x + natural.width > maxWidth {
                    y += rowHeight + lineSpacing
                    x = 0
                    rowHeight = 0
                }
                frames.append(CGRect(x: x, y: y, width: natural.width, height: natural.height))
                x += natural.width + spacing
                rowHeight = max(rowHeight, natural.height)
            }
            usedWidth = max(usedWidth, x)
        }

        let height = y + rowHeight
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: width, height: height), frames)
    }
}
