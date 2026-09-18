import SwiftUI

// Controls from `webapp/components/foundation/ui-kit/Button.tsx` and the
// form fields the web styles inline.

// MARK: - Buttons

/// Buttons are cream, because a button is a known thing and everything known
/// in this product sits on a light panel. `.ghost` is for the subordinate
/// action on a screen — one primary per view.
///
/// `.ink` inverts that for the one place the rule breaks down: a button
/// sitting ON a cream panel, where cream-on-cream would be invisible. The
/// colours swap; the meaning doesn't.
struct BPButtonStyle: ButtonStyle {
    enum Variant {
        case solid
        case ghost
        case ink
    }

    var variant: Variant = .solid
    /// Full width is the common case; turn it off to sit inline beside a field.
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        BPButtonBody(configuration: configuration, variant: variant, fullWidth: fullWidth)
    }

    private struct BPButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let fullWidth: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(.slab(18, relativeTo: .body))
                .tracking(0.72)
                .textCase(.uppercase)
                .foregroundStyle(foreground)
                .tint(foreground)
                .padding(.horizontal, 16)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
                .background(background(pressed: pressed))
                .overlay {
                    if variant == .ghost {
                        Rectangle().strokeBorder(Theme.line, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.6)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: pressed)
        }

        private var foreground: Color {
            switch variant {
            case .solid: Theme.panelFg
            case .ghost: Theme.fg
            case .ink: Theme.panel
            }
        }

        private func background(pressed: Bool) -> Color {
            switch variant {
            case .solid: pressed ? Color(hex: 0xFFFDF7) : Theme.panel
            case .ghost: pressed ? Theme.surfaceRaised : .clear
            case .ink: pressed ? Color(hex: 0x2C2921) : Theme.panelFg
            }
        }
    }
}

extension ButtonStyle where Self == BPButtonStyle {
    static var solid: BPButtonStyle { BPButtonStyle(variant: .solid) }
    static var ghost: BPButtonStyle { BPButtonStyle(variant: .ghost) }
    static var ink: BPButtonStyle { BPButtonStyle(variant: .ink) }
}

/// A button that reads as a quiet line of text — the "back home", "leave",
/// "already have an account?" tier. Mono, uppercase, underlined.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(11, weight: .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .underline()
            .foregroundStyle(Theme.fg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Fields

extension View {
    /// A text field, picker or menu sitting in a recessed well with a hairline
    /// border. The border rather than the inset shadow because a field
    /// changes state on focus; the border is carrying that state.
    func fieldStyle() -> some View {
        font(.sans(16))
            .foregroundStyle(Theme.fg)
            .tint(Theme.panel)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.surfaceRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }

    /// The small uppercase caption above a field.
    func fieldLabel() -> some View {
        monoLabel(10, weight: .bold, tracking: 0.14)
    }
}

// MARK: - Segmented choice

/// A row of mutually exclusive options. The selected one is a cream panel,
/// like a pressed key; the rest are background.
struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Read by VoiceOver as the group's name.
    var accessibilityName: String = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.slab(17, relativeTo: .body))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? Theme.panelFg : Theme.fg)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Theme.panel : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Avatars

/// A round avatar: the image if there is one, otherwise the initial in slab
/// on the accent.
struct Avatar: View {
    let name: String
    var url: URL?
    var size: CGFloat = 32
    /// Rings the avatar in red — "this one is you".
    var isMine = false

    var body: some View {
        // "Mine" is a red ring standing off the avatar by a gap, so it still
        // shows against the red fallback.
        let inner = isMine ? size - 8 : size
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().background(Theme.panelShade)
            default:
                initial(size: inner)
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(Circle())
        .frame(width: size, height: size)
        .overlay { if isMine { Circle().strokeBorder(Theme.hidden, lineWidth: 2) } }
        .accessibilityHidden(true)
    }

    private func initial(size: CGFloat) -> some View {
        ZStack {
            Theme.hidden
            // Bebas Neue's capitals sit optically high in the line box; this
            // is the web's `.font-slab-optical-center`.
            Text(String(name.prefix(1)).uppercased())
                .font(.slab(size * 0.55, relativeTo: .body))
                .foregroundStyle(Theme.panel)
                .offset(y: size * 0.55 * 0.06)
        }
    }
}
