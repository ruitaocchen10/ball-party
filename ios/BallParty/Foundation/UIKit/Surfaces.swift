import SwiftUI

// Surfaces from `webapp/components/foundation/ui-kit/` — Card, Concealed,
// Reveal, ErrorBanner, PageHeader — plus the page background from
// `globals.css`'s `body` rule.

// MARK: - Background

/// Near-black with one soft pool of light from above, like the web's `body`.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.surface
            EllipticalGradient(
                colors: [Theme.fg.opacity(0.075), .clear],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadiusFraction: 0,
                endRadiusFraction: 0.9
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// The dark page every screen sits on. Put it on the screen's root so the
    /// navigation stack's own (system) background never shows through.
    func screenBackground() -> some View {
        background { AppBackground() }
    }
}

// MARK: - Panel card

/// A card is the only light surface in the product. If something matters it
/// goes on a card; everything else is background.
///
/// The red strip along the top edge marks a card with concealed information
/// behind it, which is why it doesn't break the rule that red means hidden.
/// Pass `edge: false` when nothing is being withheld.
struct PanelCard<Content: View>: View {
    var edge = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if edge {
                Theme.hidden
                    .frame(height: 5)
                    .accessibilityHidden(true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.panelFg)
        .tint(Theme.panelFg)
        // Panels are lit objects: a drop shadow plus a 1px top highlight. The
        // highlight is why they read as raised rather than as pale rectangles.
        .background {
            // The shadow lives on the background layer alone, so it can only
            // ever be the panel's silhouette and never leaks onto its text.
            ZStack(alignment: .top) {
                Theme.panel
                Color.white.opacity(0.7).frame(height: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 12, x: 0, y: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// The name on a card: slab, uppercase, and always the biggest thing on it.
struct CardTitle: View {
    let text: String
    var size: CGFloat = 24

    var body: some View {
        Text(text)
            .slabTitle(size, color: Theme.panelFg)
            .lineSpacing(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The line under a card's name.
struct CardMeta: View {
    let text: String

    var body: some View {
        Text(text).monoLabel(11, tracking: 0.11, color: Theme.panelMuted)
    }
}

// MARK: - Concealed

/// Concealed information. Red is the one shape in the product that means
/// "somebody knows something you don't". When the thing is revealed it becomes
/// a `PanelCard`.
///
/// `label` goes to VoiceOver: hidden information still has to announce that it
/// exists, otherwise the state is invisible rather than merely secret.
struct Concealed<Content: View>: View {
    let label: String
    /// For a chip-sized use (a hidden rating inline in a stat tile) rather
    /// than a card-sized one (a Wavelength target, an auction lot). The
    /// default's card-scale shadow and 4pt inset hairline are sized for a
    /// surface with real presence; shrunk onto a chip a few points tall,
    /// that shadow blooms out past the chip itself and the hairline
    /// swallows nearly all of it. Compact keeps the same red weave — still
    /// unambiguously "hidden" — with a shadow and hairline sized to match.
    var compact = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Theme.panel)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Theme.hiddenInk
                    ConcealedWeave(band: compact ? 4 : 6, period: compact ? 8 : 12)
                }
                .shadow(
                    color: .black.opacity(compact ? 0.35 : 0.5),
                    radius: compact ? 2 : 12,
                    x: 0,
                    y: compact ? 1 : 10
                )
            }
            // The inset hairline that reads the weave as a deliberate surface.
            .overlay {
                Rectangle()
                    .inset(by: compact ? 2 : 4)
                    .stroke(Theme.panel.opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// The diagonal weave that marks concealed information: `band`-wide stripes,
/// `period` apart, running top-left to bottom-right (`.pattern-concealed`).
/// The defaults are the card-scale spec; `Concealed`'s `compact` mode tightens
/// both so more than one stripe shows across a chip-sized surface.
struct ConcealedWeave: View {
    var band: CGFloat = 6
    var period: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            // `period` is measured across the stripes; along a 45° edge the
            // stripes sit `period * √2` apart.
            let step = period * 2.0.squareRoot()
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += step
            }
            context.stroke(path, with: .color(.black.opacity(0.10)), lineWidth: band)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reveal

/// The concealed → revealed swap: a hidden value pops into its true value
/// once the server reveals it. One shared component so every game uses the
/// same timing (`reveal` / `fade` in `lib/foundation/ui-kit/motion.ts`).
struct Reveal<Hidden: View, Shown: View>: View {
    let revealed: Bool
    @ViewBuilder var concealed: Hidden
    @ViewBuilder var content: Shown

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if revealed {
                content
                    .transition(reduceMotion ? .identity : .scale(scale: 0.94).combined(with: .opacity))
            } else {
                concealed
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
    }
}

// MARK: - Wells

extension View {
    /// A recessed surface — the inverse of a panel: a shadow inset from the
    /// top instead of a highlight, and no drop shadow, because a well doesn't
    /// sit on top of anything. For passive surfaces (a clock, a stat row, an
    /// empty state); a control that changes its border on focus keeps a
    /// plain border instead.
    func well(bordered: Bool = true) -> some View {
        background {
            Rectangle().fill(Theme.surfaceRaised.shadow(.inner(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)))
        }
        .overlay {
            if bordered {
                Rectangle().strokeBorder(Theme.line, lineWidth: 1)
            }
        }
    }
}

/// A 1pt hairline in the design's line colour.
struct LineRule: View {
    var body: some View {
        Theme.line
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The dashed rule inside a panel that separates a thing's identity from its
/// numbers or actions.
struct DashedRule: View {
    var body: some View {
        Line()
            .stroke(Theme.panelLine, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// A horizontal meter: a thin track with a cream fill, like the web clock.
struct MeterBar: View {
    /// 0...1.
    let fraction: Double
    var fill: Color = Theme.panel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule()
                    .fill(fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Banners and headers

/// What a screen shows when something went wrong. Red is the accent, so the
/// error state borrows the concealed hue at low strength rather than adding a
/// second alarm colour.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.sans(14))
            .foregroundStyle(Theme.hiddenText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.hidden.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hidden.opacity(0.4), lineWidth: 1))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A consistent, compact heading for a screen: red eyebrow, slab title,
/// optional description, and a hairline under it all.
struct PageHeader: View {
    var eyebrow: String?
    let title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow).eyebrow()
            }
            Text(title)
                .slabTitle(38)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(.sans(16))
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { LineRule() }
    }
}

/// A section heading inside a screen: slab, one step under `PageHeader`.
struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .slabTitle(24)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).monoLabel(10, tracking: 0.1)
            }
        }
    }
}

/// How a revealed result went. Filled with the public grade colours, never
/// red: red means information is still concealed, a result is public.
struct ResultBadge: View {
    enum Tone {
        case good
        case bad
        case neutral

        fileprivate var fill: Color {
            switch self {
            case .good: Theme.gradeElite
            case .bad: Theme.gradeRough
            case .neutral: Theme.gradeEven
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.panel)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.fill)
    }
}

/// What a screen shows when there is nothing to show: a recessed well with a
/// slab title, a mono line saying why, and optionally one way forward.
struct EmptyState<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .slabTitle(28)
                .accessibilityAddTraits(.isHeader)
            Text(message).monoLabel(11, tracking: 0.1)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .well()
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}
