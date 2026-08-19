import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var isTrusted = AX.isTrusted
    @State private var launchAtLogin = LoginItem.isEnabled
    /// nil == the "All displays" default; otherwise the key of a specific screen.
    @State private var targetKey: String? = Settings.shared.initialEditingTarget()
    @State private var screens: [NSScreen] = NSScreen.screens

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var theme: Theme { settings.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            header
            if !isTrusted { permissionBanner }

            divider
            displayRow
            paddingCard
            presets

            divider
            options

            divider
            footer
        }
        .padding(theme.panelPadding)
        .frame(width: 360)
        .environment(\.theme, theme)
        .onReceive(ticker) { _ in tick() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            if let key = targetKey, !screens.contains(where: { Settings.key(for: $0) == key }) {
                targetKey = nil
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.dividerColor).frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Matte")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                Text(DockInfo.summary)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(PanelSwitchStyle())
                .labelsHidden()
                .fixedSize()
                .onChange(of: settings.isEnabled) { commit() }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
                .font(theme.labelFont.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Padding works by resizing other apps' windows, which macOS gates behind Accessibility.")
                .font(theme.labelFont)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Grant Access…") { AX.requestTrust() }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                Button("Open Settings") { openAccessibilitySettings() }
                    .buttonStyle(PanelButtonStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.controlRadius)
                .fill(Color.orange.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: theme.controlRadius)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: - Display

    private var displayRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Display")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 52, alignment: .leading)

                Menu {
                    Button("All displays") { targetKey = nil }
                    ForEach(screens, id: \.self) { screen in
                        Button(label(for: screen)) { targetKey = Settings.key(for: screen) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(targetScreen.map(label(for:)) ?? "All displays")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: theme.rowHeight - 4)
                    .background(
                        RoundedRectangle(cornerRadius: theme.controlRadius)
                            .fill(theme.prefersBorders ? Color.clear : theme.controlFill)
                            .overlay(RoundedRectangle(cornerRadius: theme.controlRadius)
                                .stroke(theme.border, lineWidth: 1))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let screen = targetScreen, settings.hasOverride(screen) {
                HStack(spacing: 6) {
                    Text("Custom padding for this display.")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button("Reset") {
                        settings.clearOverride(for: screen)
                        commit()
                    }
                    .buttonStyle(PanelButtonStyle())
                }
                .padding(.leading, 60)
            }
        }
        .disabled(!settings.isEnabled)
        .opacity(settings.isEnabled ? 1 : 0.45)
    }

    // MARK: - Padding

    private var paddingCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Padding")
                    .font(theme.labelFont.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    settings.editEdgesIndividually.toggle()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(PanelIconButtonStyle(isActive: settings.editEdgesIndividually))
                .help(settings.editEdgesIndividually
                      ? "Use one value for every edge"
                      : "Set each edge separately")
            }

            if settings.editEdgesIndividually {
                individualEdgeFields
            } else {
                HStack(spacing: 10) {
                    PanelSlider(value: uniformBinding, range: 0...Settings.maxPadding,
                                label: "Padding, all edges")
                    PanelNumberField(value: uniformBinding)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.controlRadius + 2)
                .fill(theme.prefersBorders ? Color.clear : theme.controlFill.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: theme.controlRadius + 2)
                    .stroke(theme.border, lineWidth: 1))
        )
        .disabled(!settings.isEnabled)
        .opacity(settings.isEnabled ? 1 : 0.45)
    }

    private var individualEdgeFields: some View {
        HStack(spacing: 6) {
            ForEach(EdgePadding.Edge.allCases) { edge in
                VStack(spacing: 4) {
                    Image(systemName: edge.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textSecondary)
                    PanelNumberField(value: binding(for: edge), width: 46)
                }
                .frame(maxWidth: .infinity)
                .help(edge.label)
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            Button("Match Dock") { matchDock() }
                .help("Adds a gap on the Dock's edge, on the display it lives on.")
            Button("Even") { setAll(40) }
            Button("Clear") { setAll(0) }
            Spacer()
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(!settings.isEnabled)
        .opacity(settings.isEnabled ? 1 : 0.45)
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Affects")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 52, alignment: .leading)
                PanelSegmented(selection: $settings.windowScope,
                               options: WindowScope.allCases.map { ($0, $0.label) })
                    .onChange(of: settings.windowScope) { commit() }
            }

            Text(settings.windowScope.help)
                .font(theme.labelFont)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show padding outline while adjusting", isOn: $settings.showOverlayOnChange)
                .toggleStyle(PanelCheckboxStyle())
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(PanelCheckboxStyle())
                .onChange(of: launchAtLogin) { LoginItem.set(launchAtLogin) }
        }
        .disabled(!settings.isEnabled)
        .opacity(settings.isEnabled ? 1 : 0.45)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Theme")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 52, alignment: .leading)
                PanelSegmented(selection: $settings.themeID,
                               options: Theme.all.map { ($0.id, $0.name) })
            }
            Text(theme.blurb)
                .font(theme.labelFont)
                .foregroundStyle(theme.textSecondary)

            HStack {
                Button("Apply Now") {
                    PaddingEngine.shared.applyToAllWindows()
                    OverlayController.shared.flash()
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .disabled(!settings.isEnabled)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }

    // MARK: - Editing target

    private var targetScreen: NSScreen? {
        guard let targetKey else { return nil }
        return screens.first { Settings.key(for: $0) == targetKey }
    }

    private var currentPadding: EdgePadding {
        if let screen = targetScreen { return settings.padding(for: screen) }
        return settings.globalPadding
    }

    private func write(_ padding: EdgePadding) {
        settings.setPadding(padding, for: targetScreen)
        commit()
    }

    private func binding(for edge: EdgePadding.Edge) -> Binding<Double> {
        Binding(
            get: { currentPadding[edge] },
            set: { newValue in
                var padding = currentPadding
                padding[edge] = clamped(newValue)
                write(padding)
            }
        )
    }

    /// Uniform mode shows the largest edge, so switching modes never silently
    /// discards a value the user set.
    private var uniformBinding: Binding<Double> {
        Binding(
            get: {
                let padding = currentPadding
                return EdgePadding.Edge.allCases.map { padding[$0] }.max() ?? 0
            },
            set: { setAll(clamped($0)) }
        )
    }

    private func setAll(_ value: Double) {
        var padding = EdgePadding.zero
        EdgePadding.Edge.allCases.forEach { padding[$0] = value }
        write(padding)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value.rounded(), 0), Settings.maxPadding)
    }

    private func label(for screen: NSScreen) -> String {
        "\(screen.localizedName) — \(Int(screen.frame.width))×\(Int(screen.frame.height))"
    }

    // MARK: - Actions

    private func matchDock() {
        guard let dockScreen = DockInfo.hostScreen() ?? NSScreen.main else { return }
        var padding = settings.padding(for: dockScreen)
        padding[DockInfo.position.edge] = DockInfo.suggestedPadding(for: dockScreen)
        settings.setPadding(padding, for: dockScreen)
        targetKey = Settings.key(for: dockScreen)
        settings.editEdgesIndividually = true
        commit()
    }

    private func commit() {
        PaddingEngine.shared.settingsChanged()
        OverlayController.shared.flash()
    }

    private func tick() {
        let trusted = AX.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted { PaddingEngine.shared.retryAfterPermissionGranted() }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
