import SwiftUI

// The game picks: the ticket-cut matchup tiles the web draws in
// `MatchupPicker.tsx`, so a game pick looks the same on both. One tile per game,
// whether it is being decided or is a call somebody made.
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

    var body: some View {
        TwoSidedFace {
            side(away)
        } home: {
            side(home)
        }
        .choiceTile(badge: false)
    }

    @ViewBuilder
    private func side(_ option: PromptOption) -> some View {
        let isSelected = selected == option.id
        let verdict: Bool? = isSelected ? winner.map { $0 == option.id } : nil
        let face = ChoiceHalf(
            code: option.teamCode, flooded: isSelected, receded: selected != nil && !isSelected,
            mark: ChoiceMark(selected: isSelected, verdict: verdict)
        )

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

// MARK: - Winner and margin

/// A Game Picks game's four choices — each team "by <7" and "by 7+" — in a grid
/// of two: the web's `MarginPicker`. The same view makes the call (`onSelect`),
/// shows one, and — once the server has graded the slot — marks it right or
/// wrong.
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
        let ink: Color = isSelected ? Color(hex: 0xFFFDF7) : Theme.fg
        let face = HStack(spacing: 8) {
            if let code = choice.teamCode {
                TeamLogo(code: code, size: 36)
                    .grayscale(passed ? 1 : 0)
                    .opacity(passed ? 0.4 : 1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.label)
                    .font(.slab(17, relativeTo: .body))
                    .textCase(.uppercase)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let sublabel = choice.sublabel {
                    Text(sublabel).monoLabel(8, tracking: 0.06, color: ink.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // The fill goes on after the tile's height, or it stops short of the border.
        .frame(maxWidth: .infinity, minHeight: ChoiceTile.height, alignment: .leading)
        .background {
            if isSelected { teamFill(choice.teamCode) } else { Theme.surfaceRaised.opacity(passed ? 0.85 : 1) }
        }
        .choiceTile(mark: ChoiceMark(selected: isSelected, verdict: verdict))

        if let onSelect {
            Button { onSelect(choice.id) } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.label). \(choice.sublabel ?? "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(choice.label)\(isSelected ? ", your call" : "")")
        }
    }
}
