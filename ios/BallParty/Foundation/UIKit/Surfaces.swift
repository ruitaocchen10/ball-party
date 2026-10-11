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

/// A card is a raised dark surface: a step lighter than the background, with a
/// hairline edge. If something matters it goes on a card; everything else is
/// background.
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.panelFg)
            .tint(Theme.panelFg)
            // The shadow lives on the background layer alone, so it can only
            // ever be the panel's silhouette and never leaks onto its text.
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.panel)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
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
                .clipShape(RoundedRectangle(cornerRadius: compact ? Theme.chipRadius : Theme.cardRadius))
                .shadow(
                    color: .black.opacity(compact ? 0.35 : 0.5),
                    radius: compact ? 2 : 12,
                    x: 0,
                    y: compact ? 1 : 10
                )
            }
            // The inset hairline that reads the weave as a deliberate surface.
            .overlay {
                RoundedRectangle(cornerRadius: compact ? Theme.chipRadius : Theme.cardRadius)
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
            RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surfaceRaised.shadow(.inner(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)))
        }
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1)
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
            .background(Theme.hidden.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.hidden.opacity(0.4), lineWidth: 1))
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
            .background(tone.fill, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
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

// MARK: - Loading

/// The app's busy indicator: a short arc turning in the current tint. It
/// replaces the stock `ProgressView`, which draws pale spokes at the system's
/// secondary grey and is nearly invisible on the dark page. It takes the
/// ambient tint, so inside a button it picks up the button's own foreground
/// (`BPButtonBody` sets it) and elsewhere it is the text colour.
struct LoadingSpinner: View {
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        let line = max(2, size / 9)
        ZStack {
            Circle().stroke(.tint.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(!reduceMotion && animating ? 360 : 0))
        }
        .frame(width: size, height: size)
        // Reduce Motion gets a slow pulse in place of the rotation.
        .opacity(reduceMotion && animating ? 0.4 : 1)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.9).repeatForever()
                : .linear(duration: 0.8).repeatForever(autoreverses: false),
            value: animating
        )
        .onAppear { animating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A status line for a screen that is waiting on someone else: a small spinner
/// beside the text, so a still screen reads as "in progress" rather than stuck.
struct WaitingNote: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 8) {
            LoadingSpinner(size: size)
            Text(text)
        }
        // The spinner is decoration; VoiceOver reads the sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A full-area wait: the spinner over a mono caption, centred. For a screen
/// that has nothing to show until its first load lands.
struct LoadingState: View {
    var label: String?

    var body: some View {
        VStack(spacing: 12) {
            LoadingSpinner(size: 28)
            if let label {
                Text(label).monoLabel(11, tracking: 0.15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Loading")
    }
}
