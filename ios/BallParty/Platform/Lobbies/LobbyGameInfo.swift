import SwiftUI

// The "Games" section under the Start a party card: what a room can play,
// for someone who has not hosted one yet. A two-column grid of art cards;
// the info button on a card opens a sheet saying what the game is. The cards
// are informational: the host picks the game inside the room.

extension MatchGame {
    /// What the game is, in a few sentences, for the info sheet. Prose from
    /// `docs/games/<game>/rules.md`; the rules themselves live on the server.
    var about: String {
        switch self {
        case .higherOrLower:
            "One card shows its fantasy points; the next hides them. Everyone calls higher or lower, then the card flips. Twelve questions, the best total wins, and ties go to sudden death."
        case .auctionTeamBuilder:
            "Bid on mystery fantasy lots to fill a roster. You see the player, year and opponent, but not the points until the lot sells. Remember how he played and price it against a limited budget."
        case .wavelength:
            "One player secretly sees a target on a spectrum and writes a one-shot clue. Their partner places the clue back on the scale. The closer you read each other, the more you score."
        }
    }

    /// Short chips under the description.
    var highlights: [String] {
        switch self {
        case .higherOrLower: ["12 questions", "Everyone at once", "Sudden death"]
        case .auctionTeamBuilder: ["Hidden points", "Fixed budget", "Fill a roster"]
        case .wavelength: ["Teams of two", "One-shot clues", "Scored on closeness"]
        }
    }
}

struct GameInfoSection: View {
    @State private var infoGame: MatchGame?

    /// The order on this screen. The room's Game tab keeps `MatchGame.allCases`.
    private let games: [MatchGame] = [.auctionTeamBuilder, .higherOrLower, .wavelength]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Games").monoLabel(11, weight: .bold, tracking: 0.14)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(games) { game in
                    GameInfoCard(game: game) { infoGame = game }
                }
            }
        }
        .sheet(item: $infoGame) { game in
            GameInfoSheet(game: game)
        }
    }
}

private struct GameInfoCard: View {
    let game: MatchGame
    let onInfo: () -> Void

    var body: some View {
        GameArt(game: game, insets: EdgeInsets(top: 30, leading: 26, bottom: 54, trailing: 26))
            .aspectRatio(1 / 1.05, contentMode: .fit)
            .overlay {
                LinearGradient(
                    colors: [Theme.surface.opacity(0.95), Theme.surface.opacity(0.1), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text(game.label)
                    .slabTitle(20)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(12)
                    .accessibilityAddTraits(.isHeader)
            }
            .overlay(alignment: .topLeading) {
                Button(action: onInfo) {
                    Image(systemName: "info")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.fg)
                        .frame(width: 28, height: 28)
                        .background(Theme.surface.opacity(0.72), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(1)
                .accessibilityLabel("About \(game.label)")
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct GameInfoSheet: View {
    let game: MatchGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(game.playersLabel).eyebrow().padding(.top, 8)
            Text(game.label).slabTitle(34)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(game.about)
                .font(.sans(15))
                .foregroundStyle(Theme.panelSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            FlowLayout(spacing: 8) {
                ForEach(game.highlights, id: \.self) { SettingPill(text: $0) }
            }
            .padding(.vertical, 16)
            Button("Got it") { dismiss() }
                .buttonStyle(.solid)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(290), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.panel)
    }
}

// MARK: - Art

/// Card art built from the games' own components, fed sample data: the
/// Wavelength dial, the Higher or Lower card pair, an auction lot. Nothing here
/// is live. The headshots are real NFL CDN images (the same two the model tests
/// use); offline or on a miss, `Portrait` falls back to a generated avatar.
private struct GameArt: View {
    let game: MatchGame
    /// Room to keep clear around the art, so a card's title and info button
    /// don't sit on top of it.
    var insets = EdgeInsets()

    var body: some View {
        ZStack {
            Theme.panel
            switch game {
            case .auctionTeamBuilder:
                Fitted(designSize: CGSize(width: 170, height: 190)) { AuctionLotSample() }
                    .padding(insets)
            case .higherOrLower:
                Fitted(designSize: CGSize(width: 312, height: 215)) { LadderPairSample() }
                    .padding(insets)
            case .wavelength:
                WavelengthDial(needle: 640, target: 600)
                    .allowsHitTesting(false)
                    .padding(insets)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Lays `content` out at a fixed design size and scales it to fit, so a real
/// component built for a full-width screen reads as a thumbnail.
private struct Fitted<Content: View>: View {
    let designSize: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / designSize.width, geo.size.height / designSize.height)
            content
                .frame(width: designSize.width, height: designSize.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private enum SampleCards {
    static let anchor = LadderCard(
        ordinal: 0, playerId: "00-0031345", displayName: "Jimmy Garoppolo", position: "QB", season: 2021, team: "SF",
        week: nil, opponent: nil,
        headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/ivz3zwvjxvgcu4dzabur",
        points: 288.4, revealedAt: Date(timeIntervalSince1970: 0)
    )
    static let challenger = LadderCard(
        ordinal: 1, playerId: "00-0032058", displayName: "Tevin Coleman", position: "RB", season: 2019, team: "SF",
        week: nil, opponent: nil,
        headshotUrl: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/wiu4r7bvhcafs9vamqc",
        points: nil, revealedAt: nil
    )
}

/// Higher or Lower: the face-up anchor beside the hidden challenger.
private struct LadderPairSample: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LadderCardView(label: "", card: SampleCards.anchor).frame(width: 150)
            LadderCardView(label: "", card: SampleCards.challenger).frame(width: 150)
        }
    }
}

/// Auction Team Builder: a lot with its player showing and its points hidden,
/// tipped a little so it reads as a different card from Higher or Lower's.
private struct AuctionLotSample: View {
    private let name = "Patrick Mahomes"
    private let headshot = URL(
        string: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/wdckwtob1lybvkmxnf7p")

    var body: some View {
        PanelCard {
            VStack(spacing: 8) {
                HStack {
                    Text("QB").slabTitle(18, color: Theme.panelFg)
                    Spacer()
                    Text("KC").monoLabel(11, weight: .bold, tracking: 0.1, color: Theme.panelMuted)
                }
                Portrait(name: name, url: headshot, size: 60)
                Text(name).slabTitle(22, color: Theme.panelFg).lineLimit(1).minimumScaleFactor(0.6)
                Concealed(label: "", compact: true) {
                    Text("? ? ?").slabTitle(28, color: Theme.fg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 44)
            }
            .padding(12)
        }
        .rotationEffect(.degrees(-6))
    }
}
