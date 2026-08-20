import SwiftUI

/// Natural height of the settings section, measured while it is collapsed so
/// the reveal has a concrete value to animate towards.
/// Height of everything except the drawer. Measured separately so the drawer's
/// animation never feeds back into the window's size.
private struct ChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct SectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var isTrusted = AX.isTrusted
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var screens: [NSScreen] = NSScreen.screens
    @State private var didFill = false
    @State private var sectionHeight: CGFloat = 0
    @State private var selectedKey: String = Settings.shared.initialEditingTarget()
        ?? Settings.key(for: NSScreen.main ?? NSScreen.screens[0])

    private let theme = Theme.current
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                paddingSection
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ChromeHeightKey.self, value: proxy.size.height)
            })
            // Bottom alignment is what makes this read as a slide. Anchored to
            // the top, a growing clip reveals the section from its first row
            // down — a wipe. Anchored to the bottom, the section sits above the
            // clip and travels down into view as the window grows, so the rest
            // of the panel stays put and only this drawer moves.
            settingsSection
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: SectionHeightKey.self, value: proxy.size.height)
                })
                .frame(height: settings.showSettingsSection ? sectionHeight : 0, alignment: .bottom)
                .clipped()

            footer
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ChromeHeightKey.self, value: proxy.size.height)
                })
        }
        .frame(width: theme.width)
        .background(theme.panelFill)
        .onPreferenceChange(SectionHeightKey.self) {
            sectionHeight = $0
            PanelMetrics.shared.drawerHeight = $0
        }
        .onPreferenceChange(ChromeHeightKey.self) { PanelMetrics.shared.chromeHeight = $0 }
        .animation(.easeOut(duration: 0.18), value: hasChanges)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedKey)
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

    // MARK: - Header

    private var header: some View {
        DisplayStrip(screens: screens,
                     selectedKey: $selectedKey.animation(.spring(response: 0.32, dampingFraction: 0.86)),
                     paddingFor: { settings.padding(for: $0) })
            .frame(maxWidth: .infinity)
            .background(theme.headerFill)
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
                if hasChanges {
                    Button {
                        resetSelected()
                    } label: {
                        HStack(spacing: 4) {
                            ResetGlyph()
                            Text("Reset").font(theme.font(11))
                        }
                        .foregroundStyle(theme.textOnGhost)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Restore the padding this display had when the panel opened")
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Button {
                    toggleFill()
                } label: {
                    Text(didFill ? "Undo" : "Fill")
                        .font(theme.font(11))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(didFill
                      ? "Put the windows back where they were"
                      : "Size every window on this display to the padded area")

                Button {
                    withAnimation(.easeOut(duration: 0.20)) {
                        settings.editEdgesIndividually.toggle()
                    }
                } label: {
                    CornerGlyph(lit: nil)
                }
                .buttonStyle(IconButtonStyle(isActive: settings.editEdgesIndividually))
                .help(settings.editEdgesIndividually
                      ? "Use one value for every edge" : "Set each edge separately")
            }

            if settings.editEdgesIndividually {
                SegmentedFieldRow(binding: binding(for:))
                    .transition(.opacity)
            } else {
                HStack(spacing: 16) {
                    PanelSlider(value: uniformBinding, range: 0...Settings.maxPadding,
                                label: "Padding, all edges")
                    numberBox(uniformBinding)
                }
                .transition(.opacity)
            }

            if !isTrusted { permissionNote }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.contentFill)
        .overlay(alignment: .top) {
            SelectionCaret(offset: caretOffset)
        }
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
            // This is the master switch, so the label has to describe the whole
            // behaviour, not sound like one feature among the others.
            Toggle("Keep windows inside the padding", isOn: $settings.isEnabled)
                .toggleStyle(PanelCheckboxStyle())
                .onChange(of: settings.isEnabled) { commit() }
            Toggle("Open new windows filled to the padding", isOn: $settings.fillNewWindows)
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
            Button("Settings") {
                // Critically damped: a drawer that overshoots would drag the
                // window's height past its target and snap back.
                withAnimation(.spring(response: 0.30, dampingFraction: 1.0)) {
                    settings.showSettingsSection.toggle()
                }
            }
                .buttonStyle(GhostButtonStyle())
            Spacer()
            Button("Apply") {
                PaddingEngine.shared.applyToAllWindows()
                OverlayController.shared.flash()
            }
            .buttonStyle(PrimaryButtonStyle())
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

    private func toggleFill() {
        if didFill {
            PaddingEngine.shared.undoFill()
            didFill = false
        } else if let screen = selectedScreen {
            didFill = PaddingEngine.shared.fillWindows(on: screen) > 0
        }
        OverlayController.shared.flash()
    }

    private var hasChanges: Bool {
        selectedScreen.map { settings.hasChanges(for: $0) } ?? false
    }

    /// Restores what this display had when the panel opened — not zero, unless
    /// zero is what it had.
    private func resetSelected() {
        guard let screen = selectedScreen else { return }
        write(settings.baseline(for: screen))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value.rounded(), 0), Settings.maxPadding)
    }

    private func commit() {
        didFill = false
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
