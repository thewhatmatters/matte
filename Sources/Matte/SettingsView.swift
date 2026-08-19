import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var isTrusted = AX.isTrusted
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var screens: [NSScreen] = NSScreen.screens
    @State private var selectedKey: String = Settings.shared.initialEditingTarget()
        ?? Settings.key(for: NSScreen.main ?? NSScreen.screens[0])

    private let theme = Theme.current
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            header
            paddingSection
            if settings.showSettingsSection { settingsSection }
            footer
        }
        .frame(width: theme.width)
        .background(theme.panelFill)
        .onReceive(ticker) { _ in tick() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            Wallpaper.invalidate()
            if !screens.contains(where: { Settings.key(for: $0) == selectedKey }) {
                selectedKey = screens.first.map(Settings.key(for:)) ?? ""
            }
        }
    }

    // MARK: - Title bar

    /// Not in the design, but the master on/off has to live somewhere visible.
    private var titleBar: some View {
        HStack {
            Text("Matte")
                .font(theme.font(12, .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Toggle("Enable padding", isOn: $settings.isEnabled)
                .toggleStyle(PanelSwitchStyle())
                .labelsHidden()
                .onChange(of: settings.isEnabled) { commit() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        DisplayStrip(screens: screens,
                     selectedKey: $selectedKey,
                     paddingFor: { settings.padding(for: $0) })
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
    }

    // MARK: - Padding

    private var paddingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Padding")
                    .font(theme.font(11, .medium))
                    .foregroundStyle(theme.textLabel)
                Spacer()
                Button {
                    resetSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text("Reset").font(theme.font(11))
                    }
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    settings.editEdgesIndividually.toggle()
                } label: {
                    EdgeGlyph(edge: .top).opacity(0)
                        .overlay { AllCornersGlyph() }
                }
                .buttonStyle(IconButtonStyle(isActive: settings.editEdgesIndividually))
                .help(settings.editEdgesIndividually
                      ? "Use one value for every edge" : "Set each edge separately")
            }

            if settings.editEdgesIndividually {
                SegmentedFieldRow(binding: binding(for:))
            } else {
                HStack(spacing: 16) {
                    PanelSlider(value: uniformBinding, range: 0...Settings.maxPadding,
                                label: "Padding, all edges")
                    numberBox(uniformBinding)
                }
            }

            if !isTrusted { permissionNote }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            SelectionCaret(offset: caretOffset)
        }
        .disabled(!settings.isEnabled)
        .opacity(settings.isEnabled ? 1 : 0.45)
    }

    private func numberBox(_ value: Binding<Double>) -> some View {
        PanelNumberField(value: value, width: 48)
            .background(RoundedRectangle(cornerRadius: theme.fieldRadius).fill(theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: theme.fieldRadius)
                .stroke(theme.fieldBorder, lineWidth: 1))
    }

    private var permissionNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Accessibility access is required to resize windows.")
                .font(theme.font(11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Button("Grant") { AX.requestTrust() }
                .buttonStyle(GhostButtonStyle())
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(theme.font(11, .medium))
                .foregroundStyle(theme.textLabel)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            Toggle("Show padding outline while adjusting", isOn: $settings.showOverlayOnChange)
                .toggleStyle(PanelCheckboxStyle())
            Toggle("Resize every window, not just large ones", isOn: allWindowsBinding)
                .toggleStyle(PanelCheckboxStyle())
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(PanelCheckboxStyle())
                .onChange(of: launchAtLogin) { LoginItem.set(launchAtLogin) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.settingsFill)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Settings") { settings.showSettingsSection.toggle() }
                .buttonStyle(GhostButtonStyle())
            Spacer()
            Button("Apply") {
                PaddingEngine.shared.applyToAllWindows()
                OverlayController.shared.flash()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!settings.isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.footerFill)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    // MARK: - State

    private var selectedScreen: NSScreen? {
        screens.first { Settings.key(for: $0) == selectedKey }
    }

    /// Centre of the selected tile, relative to the panel's centre.
    private var caretOffset: CGFloat {
        guard let index = screens.firstIndex(where: { Settings.key(for: $0) == selectedKey }) else { return 0 }
        let count = CGFloat(screens.count)
        let stride = theme.tileWidth + theme.tileGap
        let first = -(stride * (count - 1)) / 2
        return first + stride * CGFloat(index)
    }

    private var currentPadding: EdgePadding {
        selectedScreen.map { settings.padding(for: $0) } ?? settings.globalPadding
    }

    private func write(_ padding: EdgePadding) {
        settings.setPadding(padding, for: selectedScreen)
        commit()
    }

    private func binding(for edge: EdgePadding.Edge) -> Binding<Double> {
        Binding(get: { currentPadding[edge] },
                set: { newValue in
                    var padding = currentPadding
                    padding[edge] = clamped(newValue)
                    write(padding)
                })
    }

    private var uniformBinding: Binding<Double> {
        Binding(get: { EdgePadding.Edge.allCases.map { currentPadding[$0] }.max() ?? 0 },
                set: { newValue in
                    var padding = EdgePadding.zero
                    EdgePadding.Edge.allCases.forEach { padding[$0] = clamped(newValue) }
                    write(padding)
                })
    }

    private var allWindowsBinding: Binding<Bool> {
        Binding(get: { settings.windowScope == .allWindows },
                set: { settings.windowScope = $0 ? .allWindows : .largeWindows; commit() })
    }

    private func resetSelected() {
        if let screen = selectedScreen { settings.clearOverride(for: screen) }
        write(.zero)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value.rounded(), 0), Settings.maxPadding)
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
}

/// The design's four-corner bracket, used on the expand button itself.
struct AllCornersGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 12
            let paths: [[CGPoint]] = [
                [CGPoint(x: 1.5, y: 3.5), CGPoint(x: 1.5, y: 2.5), CGPoint(x: 3.5, y: 1.5)],
                [CGPoint(x: 8.5, y: 1.5), CGPoint(x: 10.5, y: 2.5), CGPoint(x: 10.5, y: 3.5)],
                [CGPoint(x: 10.5, y: 8.5), CGPoint(x: 10.5, y: 10.5), CGPoint(x: 8.5, y: 10.5)],
                [CGPoint(x: 3.5, y: 10.5), CGPoint(x: 1.5, y: 10.5), CGPoint(x: 1.5, y: 8.5)]
            ]
            for points in paths {
                var path = Path()
                path.move(to: CGPoint(x: points[0].x * s, y: points[0].y * s))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * s, y: point.y * s))
                }
                context.stroke(path, with: .color(.white),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 12, height: 12)
    }
}
