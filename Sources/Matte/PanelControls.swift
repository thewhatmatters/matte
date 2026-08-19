import SwiftUI

private let theme = Theme.current

// MARK: - Slider

/// SwiftUI's Slider has no style protocol, so a themed slider is a track, a
/// fill, a knob and a drag gesture. Accessibility is not free here.
struct PanelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String

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
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = min(max(drag.location.x - theme.knobSize / 2, 0), usable)
                    value = (range.lowerBound + (position / usable)
                             * (range.upperBound - range.lowerBound)).rounded()
                }
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
    /// The design draws a corner per field, in reading order, so each edge is
    /// paired with the corner that sits in its slot.
    static func corner(for edge: EdgePadding.Edge) -> Glyph.Corner {
        switch edge {
        case .top: return .topLeft
        case .right: return .topRight
        case .bottom: return .bottomLeft
        case .left: return .bottomRight
        }
    }

    @Binding var value: Double
    /// nil means "share the row equally" — used by the four-up edge row.
    var width: CGFloat? = 48
    var edge: EdgePadding.Edge?

    var body: some View {
        HStack(spacing: 4) {
            if let edge {
                CornerGlyph(lit: Self.corner(for: edge)).frame(width: 24, height: 24)
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
            .overlay(RoundedRectangle(cornerRadius: theme.buttonRadius)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
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
                    }
                    .frame(width: 16, height: 16)
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
