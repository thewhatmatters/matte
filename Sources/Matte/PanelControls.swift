import SwiftUI

private let theme = Theme.current

// MARK: - Slider

/// SwiftUI's Slider has no style protocol, so a themed slider is a track, a
/// fill, a knob and a drag gesture. Accessibility is not free here.
struct PanelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - theme.knobSize, 1)
            let x = usable * fraction

            ZStack(alignment: .leading) {
                Capsule().fill(theme.trackFill)
                    .frame(height: theme.trackHeight)
                Capsule().fill(theme.trackActive)
                    .frame(width: x + theme.knobSize / 2, height: theme.trackHeight)
                Circle().fill(theme.knobFill)
                    .frame(width: theme.knobSize, height: theme.knobSize)
                    .scaleEffect(isDragging ? 1.12 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: 3)
                    .offset(x: x)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isDragging)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let position = min(max(drag.location.x - theme.knobSize / 2, 0), usable)
                        value = (range.lowerBound + (position / usable)
                                 * (range.upperBound - range.lowerBound)).rounded()
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: theme.knobSize)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

// MARK: - Number field

/// TextField can't be restyled — TextFieldStyle has no usable requirement — so
/// this strips it to `.plain` and draws the surface underneath.
struct PanelNumberField: View {
    @Binding var value: Double
    /// nil means "share the row equally" — used by the four-up edge row.
    var width: CGFloat? = 48
    var edge: EdgePadding.Edge?

    var body: some View {
        HStack(spacing: 4) {
            if let edge {
                EdgeGlyph(edge: edge).frame(width: 24, height: 24)
            }
            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain)
                .font(theme.font(14))
                .foregroundStyle(theme.textPrimary)
                .accessibilityLabel(edge?.label ?? "Padding")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(width: width, height: theme.fieldHeight)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

/// Four fields sharing one rounded outline, divided by hairlines.
struct SegmentedFieldRow: View {
    let binding: (EdgePadding.Edge) -> Binding<Double>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(EdgePadding.Edge.displayOrder.enumerated()), id: \.element) { index, edge in
                PanelNumberField(value: binding(edge), width: nil, edge: edge)
                if index < EdgePadding.Edge.displayOrder.count - 1 {
                    Rectangle().fill(theme.fieldBorder)
                        .frame(width: 1, height: theme.fieldHeight)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: theme.fieldRadius).fill(theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.fieldRadius).stroke(theme.fieldBorder, lineWidth: 1)
        )
    }
}

// MARK: - Uniform field

/// The single padding input. Shows "Mixed" when the four edges disagree rather
/// than picking one of them, so collapsing the per-edge fields never implies a
/// value the padding doesn't actually have. Committing here sets all four.
struct UniformField: View {
    /// nil when the edges differ.
    let value: Double?
    let commit: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Mixed", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(theme.font(14))
            .foregroundStyle(value == nil && !isFocused ? theme.textSecondary : theme.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(width: 60, height: theme.fieldHeight)
            .background(RoundedRectangle(cornerRadius: theme.fieldRadius).fill(theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: theme.fieldRadius)
                .stroke(theme.fieldBorder, lineWidth: 1))
            .onSubmit(apply)
            .onChange(of: isFocused) { if !isFocused { apply() } }
            .onChange(of: value) { syncFromValue() }
            .onAppear(perform: syncFromValue)
            .accessibilityLabel("Padding, all edges")
            .accessibilityValue(value.map { "\(Int($0)) points" } ?? "mixed")
    }

    private func syncFromValue() {
        guard !isFocused else { return }
        text = value.map { String(Int($0)) } ?? ""
    }

    private func apply() {
        guard let entered = Double(text.trimmingCharacters(in: .whitespaces)) else {
            syncFromValue()
            return
        }
        commit(entered)
    }
}

// MARK: - Buttons

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(13))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: theme.buttonHeight)
            .background(RoundedRectangle(cornerRadius: theme.buttonRadius).fill(theme.ghostFill))
            .overlay(RoundedRectangle(cornerRadius: theme.buttonRadius)
                .stroke(theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 1, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(13))
            .foregroundStyle(theme.textOnAccent)
            .padding(.horizontal, 12)
            .frame(height: theme.buttonHeight)
            .background(RoundedRectangle(cornerRadius: theme.buttonRadius).fill(theme.accent))
            .overlay(alignment: .top) {
                // The design's inset highlight sits on the top edge only.
                Rectangle()
                    .fill(theme.accentTopHighlight)
                    .frame(height: 1)
                    .padding(.horizontal, theme.buttonRadius / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.buttonRadius))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Small 24×24 icon button; active state is a 10% white fill.
struct IconButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? theme.iconButtonActive : .clear))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Toggles

struct PanelCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(configuration.isOn ? theme.checkFill : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .stroke(configuration.isOn ? theme.checkFill : theme.fieldBorder, lineWidth: 1))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.checkMark)
                            .opacity(configuration.isOn ? 1 : 0)
                            .scaleEffect(configuration.isOn ? 1 : 0.6)
                    }
                    .frame(width: 16, height: 16)
                    .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isOn)
                configuration.label
                    .font(theme.font(12.5))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

struct PanelSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? theme.accent : theme.trackFill)
                .frame(width: 30, height: 17)
                .overlay(
                    Circle().fill(.white).frame(width: 13, height: 13)
                        .offset(x: configuration.isOn ? 6.5 : -6.5)
                )
                .animation(.spring(duration: 0.22), value: configuration.isOn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
