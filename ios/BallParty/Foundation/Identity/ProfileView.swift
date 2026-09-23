import SwiftUI

/// The Profile tab: who is signed in, their Ball Knower / Gamer highlights,
/// their take history, and the way out. Mirrors the web's `/profile` — the
/// highlights card owns a `ProfileViewModel` (`my_match_history`,
/// `my_profile_knower_highlights`), and the take history reuses the same
/// `HuddleViewModel`/`PromptDetailView` Huddle itself is built on, so a take
/// tapped here opens the identical prompt screen.
struct ProfileView: View {
    @ObservedObject var auth: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel
    @StateObject private var huddle: HuddleViewModel
    private let viewerId: UUID
    private let profileClient: ProfileClient

    @State private var editor: ProfileEditorViewModel?

    init(auth: AuthViewModel, viewerId: UUID, email: String?) {
        self.auth = auth
        self.viewerId = viewerId
        // A local, not `self.profileClient`: referencing a stored property
        // from inside `StateObject`'s escaping autoclosure would capture
        // `self` before this struct finishes initializing.
        let profileClient = SupabaseProfileClient(client: SupabaseConfig.client)
        self.profileClient = profileClient
        _viewModel = StateObject(
            wrappedValue: ProfileViewModel(client: profileClient, userId: viewerId, email: email)
        )
        _huddle = StateObject(
            wrappedValue: HuddleViewModel(client: SupabaseHuddleClient(client: SupabaseConfig.client), viewerId: viewerId)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                HighlightsCard(viewModel: viewModel)
                TakesHistory(huddle: huddle)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editor = ProfileEditorViewModel(
                            client: profileClient, userId: viewerId,
                            displayName: viewModel.profile?.displayName ?? "",
                            avatarURL: viewModel.avatarURL
                        )
                    } label: {
                        Label("Edit profile", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Theme.fg)
                }
                .accessibilityLabel("Profile menu")
            }
        }
        .sheet(item: $editor) { editorViewModel in
            ProfileEditorView(viewModel: editorViewModel) {
                Task { await viewModel.load() }
            }
        }
        .task {
            await viewModel.load()
            await huddle.load()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Portrait(name: viewModel.displayName, url: viewModel.avatarURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayName)
                    .slabTitle(38)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let email = viewModel.email, viewModel.displayName != email {
                    Text(email)
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                }
                if let joined = viewModel.joinedLabel {
                    Text(joined).monoLabel(10, tracking: 0.12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { LineRule() }
    }
}

// MARK: - Highlights

/// The Ball Knower / Gamer switchable card — `ProfileHighlightsCard` on the web.
private struct HighlightsCard: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "Highlights")
                Spacer(minLength: 8)
                if viewModel.statsView == .knower {
                    Picker("Range", selection: $viewModel.statsRange) {
                        ForEach(ProfileStatRange.allCases, id: \.self) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.fg)
                }
            }

            SegmentedChoice(
                selection: $viewModel.statsView,
                options: [.knower, .gamer],
                title: { $0 == .knower ? "Ball knower" : "Gamer" },
                accessibilityName: "Profile stat type"
            )

            if viewModel.statsView == .knower {
                knowerTiles
            } else {
                gamerTiles
            }
        }
    }

    private var knowerTiles: some View {
        VStack(spacing: 12) {
            HighlightTile(
                label: "Total points",
                value: viewModel.selectedKnowerHighlight.totalPoints.formatted(),
                detail: viewModel.statsRange.windowLabel
            )
            HighlightTile(label: "Ball knower status", value: viewModel.knowerStatus, detail: viewModel.knowerStatusDetail)
            standingTile
        }
    }

    private var standingTile: some View {
        let percentile = viewModel.selectedKnowerHighlight.percentile
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ball knower standing").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            HStack(spacing: 16) {
                PercentileRing(percentile: percentile)
                Text(percentile == nil ? "Make a correct pick to enter the rankings" : "Among active ball knowers")
                    .font(.sans(14))
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            percentile == nil ? "Not ranked yet" : "\(percentile!)th percentile among active ball knowers"
        )
    }

    private var gamerTiles: some View {
        VStack(spacing: 12) {
            HighlightTile(
                label: "Games played",
                value: "\(viewModel.gamerHighlight.gamesPlayed)",
                detail: "All-time multiplayer games"
            )
            HighlightTile(
                label: "Win rate",
                value: "\(viewModel.gamerHighlight.winRate)%",
                detail: "\(viewModel.gamerHighlight.wins) multiplayer \(viewModel.gamerHighlight.wins == 1 ? "win" : "wins")"
            )
        }
    }
}

/// One stat, in the recessed style every passive number on this screen uses.
private struct HighlightTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            Text(value)
                .slabTitle(40)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
    }
}

/// A player's lifetime-window percentile as a ring, the same 1–100 gauge the
/// web draws with an SVG circle.
private struct PercentileRing: View {
    let percentile: Int?

    var body: some View {
        let fraction = Double(max(0, min(100, percentile ?? 0))) / 100
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.hiddenText, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentile.map { "\($0)%" } ?? "—")
                .font(.slab(18))
                .foregroundStyle(Theme.fg)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

// MARK: - Take history

/// "Your takes" — every top-level comment the viewer has left on a Huddle
/// prompt, newest first, each opening the same `PromptDetailView` the feed does.
private struct TakesHistory: View {
    @ObservedObject var huddle: HuddleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Your takes")

            switch huddle.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            case .failed:
                // The rest of the profile is still useful without Huddle; a
                // failed read here just leaves the section empty rather than
                // blocking the screen.
                EmptyView()
            case .loaded:
                takes
            }
        }
    }

    @ViewBuilder
    private var takes: some View {
        let mine = PromptFeed.myTakes(in: huddle.posts)
        if mine.isEmpty {
            EmptyState(title: "No takes yet", message: "Your takes on Huddle prompts will show up here.")
        } else {
            VStack(spacing: 12) {
                ForEach(mine) { take in
                    NavigationLink {
                        PromptDetailView(viewModel: huddle, postId: take.post.id)
                    } label: {
                        TakeCardView(post: take.post, comment: take.comment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
