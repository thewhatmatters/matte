import SwiftUI

// MARK: - Slider

/// SwiftUI's Slider has no style protocol, so a themed slider has to be built
/// from a track, a fill, a knob and a drag gesture. Accessibility is not free
/// here — hence the explicit value and adjustable action.
struct PanelSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String

    @State private var isDragging = false

    private let knobSize: CGFloat = 13
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - knobSize, 1)
            let fraction = normalized
            let knobX = usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.trackFill)
                    .frame(height: trackHeight)
                    .overlay(
                        theme.prefersBorders
                            ? Capsule().stroke(theme.border, lineWidth: 1) : nil
                    )

                Capsule()
                    .fill(theme.accent)
                    .frame(width: knobX + knobSize / 2, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
                    .shadow(color: .black.opacity(isDragging ? 0.28 : 0.16),
                            radius: isDragging ? 3 : 1.5, y: 0.5)
                    .offset(x: knobX)
                    .animation(.interactiveSpring(duration: 0.18), value: isDragging)
            }
            .frame(height: max(knobSize, trackHeight))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let x = min(max(drag.location.x - knobSize / 2, 0), usable)
                        value = denormalized(x / usable)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 18)
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

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func denormalized(_ fraction: Double) -> Double {
        (range.lowerBound + fraction * (range.upperBound - range.lowerBound)).rounded()
    }
}

// MARK: - Number field

/// TextField can't be restyled (TextFieldStyle has no usable requirement), so
/// this strips it to `.plain` and draws the surface underneath.
struct PanelNumberField: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    var width: CGFloat = 52
    var alignment: TextAlignment = .center

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .font(theme.numeralFont)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 6)
            .frame(width: width, height: theme.rowHeight - 4)
            .background(
                RoundedRectangle(cornerRadius: theme.controlRadius)
                    .fill(theme.prefersBorders ? Color.clear : theme.controlFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.controlRadius)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Segmented control

struct PanelSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    @Binding var selection: T
    var options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: theme.prefersBorders ? 0 : 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(theme.labelFont)
                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: theme.rowHeight - 6)
                        .background(
                            RoundedRectangle(cornerRadius: theme.controlRadius - 1)
                                .fill(isSelected ? theme.controlFillActive : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                if theme.prefersBorders, index < options.count - 1 {
                    Rectangle().fill(theme.border).frame(width: 1, height: theme.rowHeight - 6)
                }
            }
        }
        .padding(theme.prefersBorders ? 0 : 2)
        .background(
            RoundedRectangle(cornerRadius: theme.controlRadius)
                .fill(theme.prefersBorders ? Color.clear : theme.controlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.controlRadius)
                        .stroke(theme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Switch

struct PanelSwitchStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? theme.accent : theme.trackFill)
                    .frame(width: 30, height: 17)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 13, height: 13)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                            .offset(x: configuration.isOn ? 6.5 : -6.5)
                    )
                    .animation(.spring(duration: 0.22), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A compact checkbox for secondary options, so they don't compete with the
/// primary enable switch.
struct PanelCheckboxStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(configuration.isOn ? theme.accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5)
                            .stroke(configuration.isOn ? theme.accent : theme.border, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(configuration.isOn ? 1 : 0)
                    )
                    .frame(width: 13, height: 13)
                configuration.label
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Buttons

struct PanelButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.labelFont)
            .foregroundStyle(prominent ? Color.white : theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: theme.rowHeight - 4)
            .background(
                RoundedRectangle(cornerRadius: theme.controlRadius)
                    .fill(prominent ? theme.accent
                          : (theme.prefersBorders ? Color.clear : theme.controlFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.controlRadius)
                            .stroke(prominent ? .clear : theme.border, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Rectangle())
    }
}

/// A small square icon button (the per-edge expander).
struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? theme.textPrimary : theme.textSecondary)
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: theme.controlRadius - 1)
                    .fill(isActive ? theme.controlFillActive : .clear)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
