import SwiftUI

// The prompt art: the ticket-stub matchup covers the web draws in
// `PromptTicket.tsx` and `MatchupPicker.tsx`, so a game pick looks the same on
// both. A game pick is a poster while it is being decided — big logos, the
// venue, the kickoff — and a compact strip once it is a call somebody made.
//
// Presentation only, like `PromptComponents`: whether a slot is a matchup
// (`PromptSlot.matchup`), what may be tapped and what a tap does is the
// caller's.

// MARK: - Ticket

/// The ticket-stub silhouette: opposite corners cut off (`PROMPT_TICKET_CUT_CORNERS`).
struct TicketShape: Shape {
    /// How far each cut runs along the edge it starts from, and down the one it
    /// ends on. The web's are 24 by 14; a small card takes smaller ones.
    var cutX: CGFloat = 24
    var cutY: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cutX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cutY))
        path.addLine(to: CGPoint(x: rect.maxX - cutX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cutY))
        path.closeSubpath()
        return path
    }
}

/// The dark ticket a prompt's art sits on: a soft pool of light from above and
/// faint vertical ruling, in the ticket silhouette.
struct PromptTicket<Content: View>: View {
    /// A hairline round the edge, for a ticket that sits in a grid.
    var ringed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background { TicketSurface() }
            .clipShape(TicketShape())
            .overlay {
                if ringed { TicketShape().stroke(Theme.line, lineWidth: 1) }
            }
    }
}

private struct TicketSurface: View {
    private static let cream = Color(hex: 0xFFFDF7)

    var body: some View {
        GeometryReader { proxy in
            // `radial-gradient(circle at 50% -15%, … transparent 46%)`: a circle
            // that reaches the far corner, faded out at 46% of the way there.
            let reach = (pow(proxy.size.width / 2, 2) + pow(proxy.size.height * 1.15, 2)).squareRoot() * 0.46
            ZStack {
                Theme.surface
                RadialGradient(
                    colors: [Self.cream.opacity(0.09), .clear],
                    center: UnitPoint(x: 0.5, y: -0.15), startRadius: 0, endRadius: reach
                )
                Canvas { context, size in
                    // One hairline at every fifth of the width.
                    for step in 1...5 {
                        let x = size.width * CGFloat(step) / 5
                        context.fill(
                            Path(CGRect(x: x - 1, y: 0, width: 1, height: size.height)),
                            with: .color(Self.cream.opacity(0.035))
                        )
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Team logo

/// A franchise mark from the shared `team-logos` bucket, falling back to the
/// team's code when there is no file for it or it can't be fetched.
struct TeamLogo: View {
    let code: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let url = NFLTeams.logoURL(for: code, storageBase: SupabaseConfig.projectURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: fallback
                    default: Color.clear  // still loading: no flash of the code
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(code.uppercased())
            .font(.mono(max(10, size * 0.28), weight: .bold))
            .foregroundStyle(Theme.fgMuted)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

// MARK: - Wording

enum MatchupText {
    /// `Sun 8:20 PM EDT`. Always Eastern, like the web: the league keeps its
    /// schedule in one zone, and two apps showing two zones for one game is the
    /// thing this is here to prevent.
    static func kickoff(_ date: Date?) -> String {
        guard let date else { return "Game time TBD" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "EEE h:mm a zzz"
        return formatter.string(from: date)
    }

    static func venue(_ game: NFLGame?) -> String {
        guard let stadium = game?.stadium, !stadium.isEmpty else { return "Venue TBD" }
        return stadium
    }
}

extension PromptSlot {
    /// The winning option, once the server has graded the slot.
    var winnerId: UUID? { correctOptionIds?.first }
}

// MARK: - Featured poster

/// One game as a poster: the two teams either side of an "@", the kickoff and
/// venue underneath, a Primetime tag along the top when it is one. The side a
/// player picks floods with its team's colour.
struct MatchupPoster: View {
    let away: PromptOption
    let home: PromptOption
    var game: NFLGame?
    /// The viewer's call.
    var selected: UUID?
    /// Makes the two sides tappable. `nil` is a cover: look, don't touch.
    var onSelect: ((UUID) -> Void)?

    private var interactive: Bool { onSelect != nil }

    var body: some View {
        PromptTicket {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(spacing: 0) {
                        tint(for: away)
                        tint(for: home)
                    }
                    VStack(spacing: 0) {
                        if game?.primetime == true {
                            PrimetimeChip().padding(.top, 8)
                        }
                        ZStack {
                            HStack(spacing: 0) {
                                side(away)
                                side(home)
                            }
                            atMark
                        }
                        .overlay { Theme.fg.opacity(0.2).frame(width: 1).accessibilityHidden(true) }
                    }
                }
                footer
            }
        }
        .modifier(CoverAccessibility(enabled: !interactive, label: coverLabel))
    }

    private var coverLabel: String {
        "\(away.label) at \(home.label). \(MatchupText.kickoff(game?.kickoff))"
    }

    // The colour of a side once picked, thrown across the top of the poster as
    // well as the side itself.
    @ViewBuilder
    private func tint(for option: PromptOption) -> some View {
        if selected == option.id, let color = option.teamCode.flatMap(NFLTeams.primaryColor(for:)) {
            LinearGradient(colors: [color, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }

    private var atMark: some View {
        Text("@")
            .font(.sans(13, weight: .bold))
            .foregroundStyle(Theme.fg)
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(Theme.fg.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(MatchupText.kickoff(game?.kickoff))
                .monoLabel(9, tracking: 0.14, color: Theme.fg.opacity(0.7))
            Text(MatchupText.venue(game))
                .monoLabel(9, tracking: 0.14, color: Theme.fg.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Theme.fg.opacity(0.2).frame(height: 1) }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func side(_ option: PromptOption) -> some View {
        let isSelected = selected == option.id
        let ink = isSelected ? Theme.panel : Theme.fg
        let face = VStack(spacing: 6) {
            if let code = option.teamCode {
                TeamLogo(code: code, size: 64)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 7)
            }
            Text(option.label)
                .slabTitle(24, color: ink)
                .lineSpacing(0)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if interactive {
                Text(isSelected ? "Your call" : "Pick winner")
                    .monoLabel(9, tracking: 0.12, color: ink.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)

        if let onSelect {
            Button { onSelect(option.id) } label: { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
        }
    }
}

private struct CoverAccessibility: ViewModifier {
    let enabled: Bool
    let label: String

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// The hexagonal "Primetime" tag that sits on a poster's top edge.
private struct PrimetimeChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars.fill").font(.system(size: 9, weight: .semibold))
            Text("Primetime")
        }
        .font(.mono(8, weight: .bold))
        .tracking(8 * 0.12)
        .textCase(.uppercase)
        .foregroundStyle(Theme.surface)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.fg)
        .clipShape(Hexagon())
        .overlay(Hexagon().stroke(Theme.fg.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 5, x: 0, y: 4)
        .accessibilityLabel("Primetime game")
    }

    private struct Hexagon: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Compact strip

/// One game as a strip: an oversized logo cropped behind each side, so a page
/// of sixteen calls stays scannable. It is the same view for making a call,
/// for showing one, and — once the server has graded the slot — for marking it
/// right or wrong.
struct MatchupTile: View {
    let away: PromptOption
    let home: PromptOption
    /// The viewer's call.
    var selected: UUID?
    /// The winner, once the slot is graded; `nil` until then.
    var winner: UUID?
    var onSelect: ((UUID) -> Void)?
    /// The cropped logo's size; smaller shows more of each mark.
    var logoSize: CGFloat = 104

    var body: some View {
        PromptTicket(ringed: true) {
            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 0) {
                        side(away)
                        Theme.line.frame(width: 1)
                        side(home)
                    }
                    Text("@")
                        .font(.mono(10, weight: .bold))
                        .foregroundStyle(Theme.fgMuted)
                        .frame(width: 24, height: 24)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                        .accessibilityHidden(true)
                }
                .frame(height: 64)
                Theme.line.opacity(0.7).frame(height: 1).padding(.horizontal, 8).padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func side(_ option: PromptOption) -> some View {
        let isSelected = selected == option.id
        let passed = selected != nil && !isSelected
        let verdict: Bool? = isSelected ? winner.map { $0 == option.id } : nil
        // The logo sits in an overlay, not in the layout: it is far bigger than
        // the strip and cropped by it, so it must not set the side's width.
        let face = Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                if isSelected, let color = option.teamCode.flatMap(NFLTeams.primaryColor(for:)) {
                    LinearGradient(colors: [color, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Theme.surface.opacity(0.85)
                }
            }
            .overlay {
                if let code = option.teamCode {
                    TeamLogo(code: code, size: logoSize)
                        .grayscale(passed ? 1 : 0)
                        .opacity(passed ? 0.4 : 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                // A filled badge: the grade colours alone vanish into a dark
                // or team-coloured side.
                if let verdict {
                    Image(systemName: verdict ? "checkmark" : "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Theme.panel)
                        .frame(width: 16, height: 16)
                        .background(verdict ? Theme.gradeElite : Theme.gradeRough, in: Circle())
                        .padding(5)
                }
            }
            .clipped()
            .overlay {
                if let verdict {
                    Rectangle().strokeBorder(verdict ? Theme.gradeElite : Theme.gradeRough, lineWidth: 1)
                }
            }

        if let onSelect {
            Button { onSelect(option.id) } label: { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: option, isSelected: isSelected, verdict: verdict))
        }
    }

    private func accessibilityLabel(for option: PromptOption, isSelected: Bool, verdict: Bool?) -> String {
        guard isSelected else { return option.label }
        switch verdict {
        case .some(true): return "\(option.label), your pick, correct"
        case .some(false): return "\(option.label), your pick, incorrect"
        case .none: return "\(option.label), your pick"
        }
    }
}

// MARK: - A set of games

/// A weekly slate as a row of posters to swipe through, with the web's dots
/// underneath. The poster it is sized from is drawn invisibly first, so the
/// pager takes exactly a poster's height — Dynamic Type included.
struct MatchupCarousel: View {
    let slots: [PromptSlot]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            if let first = slots.first?.matchup {
                MatchupPoster(away: first.away, home: first.home, game: slots[0].game)
                    .hidden()
                    .overlay {
                        TabView(selection: $index) {
                            ForEach(Array(slots.enumerated()), id: \.element.id) { position, slot in
                                if let matchup = slot.matchup {
                                    MatchupPoster(away: matchup.away, home: matchup.home, game: slot.game)
                                        .tag(position)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
            }
            HStack(spacing: 6) {
                ForEach(slots.indices, id: \.self) { position in
                    Rectangle()
                        .fill(position == index ? Theme.panel : Theme.line)
                        .frame(width: position == index ? 24 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.15), value: index)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Game \(index + 1) of \(slots.count)")
        }
    }
}

// MARK: - Winner and margin

/// A Game Picks game's four choices — each team "by <7" and "by 7+" — in a grid
/// of two: the web's `MarginPicker`. The same view makes the call (`onSelect`),
/// shows one, and — once the server has graded the slot — marks it right or
/// wrong. The cover above it is `MatchupPoster`'s.
struct MarginChoices: View {
    let slot: PromptSlot
    let game: MarginGame
    /// The viewer's call.
    var selected: UUID?
    /// Whether to mark the call right or wrong; only once the slot is graded.
    var reveals = false
    var onSelect: ((UUID) -> Void)?

    /// A graded slot with no right answer: a tied game on a weekly slate. It
    /// voids the pick for everyone.
    private var isNoContest: Bool { reveals && slot.correctOptionIds?.isEmpty == true }

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(game.choices) { choice in
                    tile(choice)
                }
            }
            if isNoContest {
                Text("No contest — game tied").monoLabel(9, tracking: 0.1)
            }
        }
    }

    @ViewBuilder
    private func tile(_ choice: PromptOption) -> some View {
        let isSelected = selected == choice.id
        let passed = selected != nil && !isSelected
        let verdict: Bool? = reveals && isSelected ? slot.isCorrect(choice.id) : nil
        let color = choice.teamCode.flatMap(NFLTeams.primaryColor(for:))
        let ink: Color = isSelected ? Color(hex: 0xFFFDF7) : Theme.fg
        let face = HStack(spacing: 8) {
            if let code = choice.teamCode {
                TeamLogo(code: code, size: 36)
                    .grayscale(passed ? 1 : 0)
                    .opacity(passed ? 0.4 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label)
                    .font(.slab(17, relativeTo: .body))
                    .textCase(.uppercase)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let sublabel = choice.sublabel {
                    Text(sublabel).monoLabel(8, tracking: 0.06, color: ink.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background {
            if isSelected, let color {
                LinearGradient(colors: [color, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Theme.surfaceRaised.opacity(passed ? 0.85 : 1)
            }
        }
        .clipShape(TicketShape(cutX: 12, cutY: 8))
        .overlay {
            TicketShape(cutX: 12, cutY: 8)
                .stroke(ring(verdict: verdict, selected: isSelected), lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            if let verdict {
                Image(systemName: verdict ? "checkmark" : "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(verdict ? Theme.gradeElite : Theme.gradeRough)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }

        if let onSelect {
            Button { onSelect(choice.id) } label: { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.label). \(choice.sublabel ?? "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(choice.label)\(isSelected ? ", your call" : "")")
        }
    }

    private func ring(verdict: Bool?, selected: Bool) -> Color {
        if let verdict { return verdict ? Theme.gradeElite : Theme.gradeRough }
        return selected ? Theme.fg.opacity(0.7) : Theme.line
    }
}

// MARK: - Everything else

/// The candidates of a prompt that isn't a set of matchups, as a short strip of
/// badges with a "+n" for the rest.
struct OptionStrip: View {
    let options: [PromptOption]
    var limit = 6

    var body: some View {
        let shown = options.prefix(limit)
        HStack(spacing: 8) {
            ForEach(Array(shown)) { OptionBadge(option: $0, size: 32) }
            if options.count > limit {
                Text("+\(options.count - limit)")
                    .font(.mono(10))
                    .foregroundStyle(Theme.fgMuted)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
            }
        }
        .frame(maxWidth: .infinity)
    }
}
