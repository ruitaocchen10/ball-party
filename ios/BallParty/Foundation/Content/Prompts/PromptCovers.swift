import SwiftUI

// The art across the top of a prompt's feed card. The web draws the same
// banners in `PromptCover.tsx` and `MatchupBanner.tsx`: a short, full-bleed
// strip with a colored glow on each side, the kind's motif or its teams, and no
// words, because the card's title and subtitle sit right under it. Every kind
// is the same height, so a feed of different kinds keeps one rhythm and a phone
// fits a couple of cards at once.

/// The height every feed card's art shares (`PROMPT_ART_HEIGHT` on the web).
enum PromptArt {
    static let height: CGFloat = 112

    static let blue = Color(hex: 0x3B82F6)
    static let red = Color(hex: 0xEF4444)
    static let green = Color(hex: 0x4ADE80)
    /// The deeper green behind the Power Rankings arrow (Tailwind green-500 on the web).
    static let greenBase = Color(hex: 0x22C55E)
}

/// A glow on each side, under whatever the banner draws.
struct PromptGlow: View {
    var left: Color = PromptArt.blue
    var right: Color = PromptArt.red
    var leftOpacity = 0.24
    var rightOpacity = 0.22

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [left.opacity(leftOpacity), .clear], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, right.opacity(rightOpacity)], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// A small label on top of the art: the card's timer or state in the top-right
/// corner, a tag like "Primetime" in the top-left. A dark scrim so it reads on
/// whatever is behind it (`Badge tone="scrim"` on the web); `success` is the
/// green of a completed card.
struct ArtChip<Content: View>: View {
    enum Tone { case scrim, success }

    var tone: Tone = .scrim
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            content
        }
        .monoLabel(9, weight: .bold, tracking: 0.1, color: Theme.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            switch tone {
            case .scrim: Theme.surface.opacity(0.8)
            case .success: Theme.gradeElite
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
        .overlay {
            if tone == .scrim { RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.line, lineWidth: 1) }
        }
    }
}

extension ArtChip where Content == Text {
    init(_ text: String, tone: Tone = .scrim, systemImage: String? = nil) {
        self.init(tone: tone, systemImage: systemImage) { Text(text) }
    }
}

// MARK: - Weekly Awards

/// Six medals, one per award, blue on the left and red on the right at mixed sizes
/// and tilts. Left, edge in: Offensive player (football), Defensive player
/// (shield), Biggest winner (trophy). Right: Best game (flame), Biggest loser
/// (thumbs down), LVP (an L). No words: the card's title sits right under it.
/// Matches the web's `WeeklyAwardsBanner`.
struct WeeklyAwardsCover: View {
    private enum Icon { case symbol(String), letterL }
    private struct Place { let icon: Icon; let color: Color; let size: CGFloat; let x: CGFloat; let y: CGFloat; let angle: Double; let fromRight: Bool }

    /// `x` is how far in from the medal's own edge and `y` how far down, as
    /// fractions of the banner, so the spread follows its width.
    private static let medals = [
        Place(icon: .symbol("american.football.fill"), color: PromptArt.blue, size: 34, x: 0.05, y: 0.39, angle: -10, fromRight: false),
        Place(icon: .symbol("shield.fill"), color: PromptArt.blue, size: 48, x: 0.17, y: 0.25, angle: 6, fromRight: false),
        Place(icon: .symbol("trophy.fill"), color: PromptArt.blue, size: 64, x: 0.32, y: 0.05, angle: -4, fromRight: false),
        Place(icon: .symbol("flame.fill"), color: PromptArt.red, size: 64, x: 0.32, y: 0.12, angle: 5, fromRight: true),
        Place(icon: .symbol("hand.thumbsdown.fill"), color: PromptArt.red, size: 48, x: 0.17, y: 0.32, angle: -7, fromRight: true),
        Place(icon: .letterL, color: PromptArt.red, size: 34, x: 0.05, y: 0.45, angle: 9, fromRight: true),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PromptGlow()
                ForEach(Array(Self.medals.enumerated()), id: \.offset) { _, medal in
                    // A medal is its ribbon and its disc: 1.38 discs tall.
                    let height = medal.size * 1.38
                    Medal(color: medal.color, size: medal.size) { icon(medal) }
                        .rotationEffect(.degrees(medal.angle))
                        .position(
                            x: medal.fromRight ? proxy.size.width * (1 - medal.x) - medal.size / 2 : proxy.size.width * medal.x + medal.size / 2,
                            y: proxy.size.height * medal.y + height / 2
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly Awards")
    }

    @ViewBuilder
    private func icon(_ medal: Place) -> some View {
        switch medal.icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: medal.size * 0.5, weight: .bold)).foregroundStyle(.white)
        case .letterL:
            LetterL().fill(.white).frame(width: medal.size * 0.5, height: medal.size * 0.5)
        }
    }
}

/// A medal: a ribbon over a shaded disc, with the award's icon on it.
private struct Medal<Icon: View>: View {
    let color: Color
    let size: CGFloat
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(spacing: -size * 0.12) {
            MedalRibbon()
                .fill(color.opacity(0.85))
                .frame(width: size, height: size / 2)
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [color, color.opacity(0.55)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.8
                ))
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 3)
                icon
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.65), radius: 5, x: 0, y: 5)
        }
        .frame(width: size)
    }
}

/// The two tails of a medal's ribbon, on the web's 40x20 grid.
private struct MedalRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 40
        let h = rect.height / 20
        var path = Path()
        path.move(to: CGPoint(x: 6 * w, y: 0))
        path.addLine(to: CGPoint(x: 16 * w, y: 0))
        path.addLine(to: CGPoint(x: 24 * w, y: 20 * h))
        path.addLine(to: CGPoint(x: 14 * w, y: 20 * h))
        path.closeSubpath()
        path.move(to: CGPoint(x: 34 * w, y: 0))
        path.addLine(to: CGPoint(x: 24 * w, y: 0))
        path.addLine(to: CGPoint(x: 16 * w, y: 20 * h))
        path.addLine(to: CGPoint(x: 26 * w, y: 20 * h))
        path.closeSubpath()
        return path
    }
}

/// A bold letter L, drawn as a shape so the cover stays wordless.
private struct LetterL: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 24
        let h = rect.height / 24
        var path = Path()
        path.move(to: CGPoint(x: 7 * w, y: 3 * h))
        path.addLine(to: CGPoint(x: 12 * w, y: 3 * h))
        path.addLine(to: CGPoint(x: 12 * w, y: 16 * h))
        path.addLine(to: CGPoint(x: 18 * w, y: 16 * h))
        path.addLine(to: CGPoint(x: 18 * w, y: 21 * h))
        path.addLine(to: CGPoint(x: 7 * w, y: 21 * h))
        path.closeSubpath()
        return path
    }
}

/// Six "!" speech bubbles, blue calling from the left and red from the right at
/// mixed sizes and tilts, the biggest nearest the middle. No words: the card's
/// title sits right under it. Matches the web's `BoldPredictionsBanner`.
struct BoldPredictionsCover: View {
    private struct Place { let color: Color; let size: CGFloat; let x: CGFloat; let y: CGFloat; let angle: Double; let fromRight: Bool }

    /// `x` is how far in from the bubble's own edge and `y` how far down, as
    /// fractions of the banner, so the spread follows its width.
    private static let bubbles = [
        Place(color: PromptArt.blue, size: 34, x: 0.04, y: 0.44, angle: -8, fromRight: false),
        Place(color: PromptArt.blue, size: 50, x: 0.15, y: 0.22, angle: 5, fromRight: false),
        Place(color: PromptArt.blue, size: 68, x: 0.29, y: 0.03, angle: -5, fromRight: false),
        Place(color: PromptArt.red, size: 68, x: 0.29, y: 0.10, angle: 6, fromRight: true),
        Place(color: PromptArt.red, size: 50, x: 0.15, y: 0.34, angle: -6, fromRight: true),
        Place(color: PromptArt.red, size: 34, x: 0.04, y: 0.48, angle: 9, fromRight: true),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PromptGlow()
                ForEach(Array(Self.bubbles.enumerated()), id: \.offset) { _, bubble in
                    let height = bubble.size * 0.9
                    SpeechBubble(color: bubble.color)
                        .frame(width: bubble.size, height: height)
                        .rotationEffect(.degrees(bubble.angle))
                        .position(
                            x: bubble.fromRight ? proxy.size.width * (1 - bubble.x) - bubble.size / 2 : proxy.size.width * bubble.x + bubble.size / 2,
                            y: proxy.size.height * bubble.y + height / 2
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bold Predictions")
    }
}

/// A speech bubble with an exclamation mark, tail at the lower left, on the web's 40x36 grid.
private struct SpeechBubble: View {
    let color: Color

    var body: some View {
        ZStack {
            BubbleBody().fill(color.opacity(0.9))
            GeometryReader { proxy in
                let w = proxy.size.width / 40
                let h = proxy.size.height / 36
                RoundedRectangle(cornerRadius: 2.2 * w).fill(.white)
                    .frame(width: 4.4 * w, height: 12 * h)
                    .position(x: 20.2 * w, y: 13 * h)
                Circle().fill(.white)
                    .frame(width: 4.8 * w, height: 4.8 * w)
                    .position(x: 20.2 * w, y: 23 * h)
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 5, x: 0, y: 5)
    }
}

private struct BubbleBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 40
        let h = rect.height / 36
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 1 * w, y: 2 * h, width: 38 * w, height: 26 * h), cornerSize: CGSize(width: 5 * w, height: 5 * h))
        path.move(to: CGPoint(x: 11 * w, y: 26 * h))
        path.addLine(to: CGPoint(x: 11 * w, y: 35 * h))
        path.addLine(to: CGPoint(x: 20 * w, y: 28 * h))
        path.closeSubpath()
        return path
    }
}

// MARK: - A game

/// One game as a broadcast graphic: each club's color runs in from its edge with
/// its logo drawn oversized and bleeding off the side, and the two names sit big
/// in the middle over the kickoff and venue. A Primetime tag sits in the
/// top-left corner, opposite the card's timer.
struct MatchupBanner: View {
    let away: PromptOption
    let home: PromptOption
    var game: NFLGame?

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: color(for: away), location: 0),
                    .init(color: .clear, location: 0.42),
                    .init(color: .clear, location: 0.58),
                    .init(color: color(for: home), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(away.label).slabTitle(22).lineLimit(1).minimumScaleFactor(0.6)
                    Text("@").font(.sans(13, weight: .bold)).foregroundStyle(Theme.fgMuted).accessibilityHidden(true)
                    Text(home.label).slabTitle(22).lineLimit(1).minimumScaleFactor(0.6)
                }
                VStack(spacing: 1) {
                    Text(MatchupText.kickoff(game?.kickoff)).monoLabel(9, tracking: 0.14, color: Theme.fg.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(MatchupText.venue(game)).monoLabel(9, tracking: 0.14, color: Theme.fg.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            // Clear of the oversized logos either side, and of the chips above.
            .padding(.horizontal, 96)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .overlay(alignment: .leading) { logo(away).offset(x: -28) }
        .overlay(alignment: .trailing) { logo(home).offset(x: 28) }
        .overlay(alignment: .topLeading) {
            if game?.primetime == true {
                ArtChip("Primetime", systemImage: "moon.stars.fill").padding(8)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(away.label) at \(home.label). \(MatchupText.kickoff(game?.kickoff))")
    }

    @ViewBuilder
    private func logo(_ option: PromptOption) -> some View {
        if let code = option.teamCode { TeamLogo(code: code, size: 128) }
    }

    /// A club's own color, so it isn't a token; a club without one leaves its side bare.
    private func color(for option: PromptOption) -> Color {
        option.teamCode.flatMap(NFLTeams.primaryColor(for:)) ?? .clear
    }
}

/// A weekly slate as one banner: the number of games as the headline, with the
/// clubs of the first four games fanned out beside it. Which games those are
/// doesn't matter, so it is the first four in the prompt's order. A still, not a
/// pager: the detail screen is where a player goes through the games.
struct SlateBanner: View {
    let games: [(away: PromptOption, home: PromptOption)]

    private static let gamesShown = 4

    init(slots: [PromptSlot]) {
        games = slots.compactMap(\.matchup)
    }

    var body: some View {
        let clubs = games.prefix(Self.gamesShown).flatMap { [$0.away, $0.home] }
        ZStack {
            PromptGlow(leftOpacity: 0.2, rightOpacity: 0.18)
            GeometryReader { proxy in
                // What is left beside the count and its label (the label is the wider of the two), split between the logos, up to a cap.
                let size = min(48, max(24, (proxy.size.width - 32 - 16 - 112) / (CGFloat(max(clubs.count, 1)) * 0.85)))
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(games.count)").slabTitle(52).lineLimit(1)
                        Text(games.count == 1 ? "Game this week" : "Games this week").monoLabel(9, tracking: 0.14)
                    }
                    .fixedSize()
                    HStack(spacing: -size * 0.15) {
                        ForEach(Array(clubs.enumerated()), id: \.offset) { _, club in
                            if let code = club.teamCode { TeamLogo(code: code, size: size) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                // Centered in what is left under the chip row, so the label is never cut off.
                .padding(.top, 24)
                .padding(.bottom, 8)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(games.count) games")
    }
}

// MARK: - Everything else

/// The candidates of a prompt that isn't a set of matchups, as a row of badges
/// on the same glow, with how many picks there are and how many more candidates
/// there are than fit.
struct OptionBanner: View {
    let options: [PromptOption]
    var pickCount = 1
    private static let limit = 6

    var body: some View {
        ZStack {
            PromptGlow()
            HStack(spacing: 8) {
                ForEach(Array(options.prefix(Self.limit))) { OptionBadge(option: $0, size: 48) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .overlay(alignment: .topLeading) {
            if pickCount > 1 { ArtChip("\(pickCount) picks to make").padding(8) }
        }
        .overlay(alignment: .bottomLeading) {
            if options.count > Self.limit { ArtChip("+\(options.count - Self.limit) more").padding(8) }
        }
        .clipped()
    }
}
