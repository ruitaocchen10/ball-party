import SwiftUI

// Controls from `webapp/components/foundation/ui-kit/Button.tsx` and the
// form fields the web styles inline.

// MARK: - Buttons

/// Buttons are a light fill on the dark page. `.ghost` is for the subordinate
/// action on a screen — one primary per view.
///
/// `.ink` is the same light fill for a button sitting ON a panel, where a
/// dark-on-dark button would be invisible.
struct BPButtonStyle: ButtonStyle {
    enum Variant {
        case solid
        case ghost
        case ink
        /// A dark fill for a button on a light card, where `.ink` would vanish.
        case dark
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
                .background(background(pressed: pressed), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay {
                    if variant == .ghost {
                        RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .opacity(isEnabled ? 1 : 0.6)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: pressed)
        }

        private var foreground: Color {
            switch variant {
            case .solid: Theme.surface
            case .ghost: Theme.fg
            case .ink: Theme.panel
            case .dark: Theme.fg
            }
        }

        private func background(pressed: Bool) -> Color {
            switch variant {
            case .solid: pressed ? Theme.panelInkHover : Theme.fg
            case .ghost: pressed ? Theme.surfaceRaised : .clear
            case .ink: pressed ? Theme.panelInkHover : Theme.panelFg
            case .dark: pressed ? Theme.panelHover : Theme.surface
            }
        }
    }
}

extension ButtonStyle where Self == BPButtonStyle {
    static var solid: BPButtonStyle { BPButtonStyle(variant: .solid) }
    static var ghost: BPButtonStyle { BPButtonStyle(variant: .ghost) }
    static var ink: BPButtonStyle { BPButtonStyle(variant: .ink) }
    static var dark: BPButtonStyle { BPButtonStyle(variant: .dark) }
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
    func fieldStyle(font: Font = .sans(16)) -> some View {
        self.font(font)
            .foregroundStyle(Theme.fg)
            .tint(Theme.fg)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// The small uppercase caption above a field.
    func fieldLabel() -> some View {
        monoLabel(10, weight: .bold, tracking: 0.14)
    }

    /// `fieldStyle` for a dropdown: its value is set in the slab face, like the
    /// buttons and segmented choices around it, not in body type.
    func menuFieldStyle() -> some View {
        textCase(.uppercase)
            .fieldStyle(font: .slab(18, relativeTo: .body))
    }
}

// MARK: - Counted text area

/// A captioned multi-line box with a running `n/limit` count under it: the
/// "Add a take" box on prompts and lists, the bold prediction box. The text
/// starts at the top left and the box is never shorter than `lines.lowerBound`
/// lines, empty or not; input past `limit` is cut off.
struct CountedTextArea: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let limit: Int
    var lines: ClosedRange<Int> = 2...5
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).fieldLabel()
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lines)
                .disabled(isDisabled)
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines.lowerBound) * 22, alignment: .topLeading)
                .padding(.vertical, 12)
                .fieldStyle()
                .onChange(of: text) { _, value in
                    if value.count > limit { text = String(value.prefix(limit)) }
                }
                .accessibilityLabel(label)
            Text("\(text.count)/\(limit)")
                .monoLabel(10, tracking: 0.08)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Segmented choice

/// A row of mutually exclusive options. The selected one is a red fill,
/// like a pressed key; the rest are background.
struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Read by VoiceOver as the group's name.
    var accessibilityName: String = ""
    /// A capsule track with a capsule selection, like the web's profile
    /// toggle, instead of the 8px segmented row.
    var pill = false

    var body: some View {
        if pill { pillBody } else { segmentedBody }
    }

    private var pillBody: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.slab(15, relativeTo: .body))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? Theme.fg : Theme.fgMuted)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isSelected ? Theme.hidden : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }

    private var segmentedBody: some View {
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
                        .foregroundStyle(Theme.fg)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Theme.hidden : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Tab bar

/// Underlined tabs: the selected one is red with a 4pt red rule under it; the
/// others have none, just a hairline along the bottom of the whole bar. Web's `TabBar`. The profile's sections use it, and
/// the leaderboard attaches one to its header.
struct TabBar<Value: Hashable>: View {
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
                        .monoLabel(11, weight: .bold, tracking: 0.14, color: isSelected ? Theme.hiddenText : Theme.fgMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(isSelected ? Theme.hidden : .clear).frame(height: 4)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { LineRule() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Navigation bar with tabs

extension View {
    /// A navigation bar variation with a `TabBar` attached under it: the bar
    /// loses its bottom rule and the tabs sit on the same solid surface, so the
    /// two read as one block, closed by the tabs' hairline.
    func tabsUnderNavigationBar<Value: Hashable>(
        selection: Binding<Value>,
        options: [Value],
        title: @escaping (Value) -> String,
        accessibilityName: String = ""
    ) -> some View {
        background(NavigationBarWithoutRule())
            .safeAreaInset(edge: .top, spacing: 0) {
                TabBar(selection: selection, options: options, title: title, accessibilityName: accessibilityName)
                    .background(Theme.surface)
            }
    }
}

/// Swaps the hosting screen's navigation bar appearance for the rule-less one.
/// SwiftUI has no modifier for the bar's shadow, so this reaches the
/// `UINavigationItem` through a zero-size view controller.
private struct NavigationBarWithoutRule: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let appearance = Theme.navigationBarAppearance(hairline: false)
            let item = navigationController?.topViewController?.navigationItem
            item?.standardAppearance = appearance
            item?.scrollEdgeAppearance = appearance
            item?.compactAppearance = appearance
        }
    }
}

// MARK: - Menu pill

/// A dropdown drawn as a capsule, to sit beside pill controls (the stats
/// card's range, the leaderboard's window).
struct MenuPill<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(title(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .font(.sans(13))
        .foregroundStyle(Theme.fg)
        .tint(Theme.fg)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Avatars

/// A round avatar: the image if there is one, otherwise the generated picture for the player's
/// name (`GeneratedAvatar`, the same one web draws).
struct Avatar: View {
    let name: String
    var url: URL?
    var size: CGFloat = 32
    /// Rings the avatar in red — "this one is you".
    var isMine = false

    var body: some View {
        // "Mine" is a red ring standing off the avatar by a gap, so it still
        // shows against any fallback.
        let inner = isMine ? size - 8 : size
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().background(Theme.panelShade)
            default:
                GeneratedAvatarView(name: name)
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(Circle())
        .frame(width: size, height: size)
        .overlay { if isMine { Circle().strokeBorder(Theme.hidden, lineWidth: 2) } }
        .accessibilityHidden(true)
    }
}


// MARK: - Pills

/// Lays its children in rows, wrapping to the next row when one fills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

/// A read-only setting: a red-outlined pill, as on a game's card.
struct SettingPill: View {
    let text: String

    var body: some View {
        Text(text)
            .monoLabel(10, weight: .bold, tracking: 0.06, color: Theme.hiddenText)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Theme.hidden, lineWidth: 1))
    }
}

/// Mutually exclusive options as pills that wrap. The chosen one is a red fill,
/// like a pressed key in `SegmentedChoice`; the rest are outlined.
struct PillChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Read by VoiceOver as the group's name.
    var accessibilityName: String = ""

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .monoLabel(11, weight: .bold, tracking: 0.06, color: Theme.fg)
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isSelected ? Theme.hidden : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? Theme.hidden : Theme.line, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}


/// A captioned figure on a raised tile: the per-seat numbers on a player's tab.
struct StatTile: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).monoLabel(9, weight: .bold, tracking: 0.12)
            Text(value).slabTitle(26).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
