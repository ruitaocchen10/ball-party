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
    @State private var confirmingDelete = false
    @State private var deleteFailed = false

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
                            avatarURL: viewModel.avatarURL,
                            username: viewModel.profile?.username
                        )
                    } label: {
                        Label("Edit profile", systemImage: "pencil")
                    }
                    Divider()
                    Link(destination: SiteLinks.privacyPolicy) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    Link(destination: SiteLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete account", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Theme.fg)
                }
                .accessibilityLabel("Profile menu")
            }
        }
        .confirmationDialog(
            "Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Permanently delete my account", role: .destructive) {
                Task {
                    if await !auth.deleteAccount() { deleteFailed = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your display name and photo and signs you out everywhere. Your past matches and takes stay on record under “Deleted player.” This can’t be undone.")
        }
        .alert("We couldn’t delete your account", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
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

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.displayName)
                    .slabTitle(38)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    // Bebas Neue's line box includes generous space below its glyphs.
                    .padding(.bottom, -6)
                    .accessibilityAddTraits(.isHeader)
                if let usernameLabel = viewModel.usernameLabel {
                    Text(usernameLabel)
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                }
                if let email = viewModel.email, viewModel.displayName != email {
                    Text(email)
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                }
                if let joined = viewModel.joinedLabel {
                    Text(joined).monoLabel(10, tracking: 0.12)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { LineRule() }
    }
}

// MARK: - Profile stats

/// The Ball Knower / Gamer dashboard. Unlike the web profile card, which can
/// let its three tiles wrap on a wide-enough viewport, a phone never has the
/// width for that — so the two smaller tiles sit side by side and the richer
/// third (the standing ring / streak) gets its own full-width row beneath
/// them, instead of a horizontal scroller that hides it off-screen.
private struct HighlightsCard: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(text: "Your stats")

            HStack(spacing: 12) {
                SegmentedChoice(
                    selection: $viewModel.statsView,
                    options: [.knower, .gamer],
                    title: { $0 == .knower ? "Ball knower" : "Gamer" },
                    accessibilityName: "Profile stat type"
                )

                // Kept in the layout (just hidden) on Gamer rather than
                // removed outright — SegmentedChoice's buttons are
                // `maxWidth: .infinity`, so if this view actually left the
                // HStack, the toggle would stretch to claim its space and
                // visibly resize on every tab switch.
                rangeMenu
                    .opacity(viewModel.statsView == .knower ? 1 : 0)
                    .allowsHitTesting(viewModel.statsView == .knower)
                    .accessibilityHidden(viewModel.statsView != .knower)
            }

            if viewModel.statsView == .knower {
                knowerTiles
            } else {
                gamerTiles
            }
        }
    }

    /// The reporting-range control, restyled to match `SegmentedChoice`'s
    /// bordered well instead of looking like a bare system menu next to it.
    private var rangeMenu: some View {
        Picker("Range", selection: $viewModel.statsRange) {
            ForEach(ProfileStatRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.menu)
        .monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.fg)
        .tint(Theme.fg)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .well()
        .fixedSize()
    }

    private var knowerTiles: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HighlightTile(
                    label: "Total points",
                    value: viewModel.selectedKnowerHighlight.totalPoints.formatted(),
                    detail: viewModel.statsRange.windowLabel
                )
                HighlightTile(label: "Ball knower status", value: viewModel.knowerStatus, detail: viewModel.knowerStatusDetail)
            }
            standingTile
            leaderboardLink
        }
    }

    /// Opens the leaderboard on whichever range the card is showing. Part of
    /// `knowerTiles`, so the Gamer half never offers it.
    private var leaderboardLink: some View {
        NavigationLink {
            LeaderboardView(initialWindow: LeaderboardWindow(viewModel.statsRange))
        } label: {
            HStack {
                Text("View leaderboard").monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.fg)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.fgMuted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .well()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var standingTile: some View {
        let percentile = viewModel.selectedKnowerHighlight.percentile
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ball knower standing").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            HStack(spacing: 16) {
                PercentileRing(percentile: percentile)
                Text(
                    percentile == nil
                        ? "Make a correct pick to enter the rankings"
                        : "\(viewModel.statsRange.label) · among active ball knowers"
                )
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
            percentile == nil ? "Not ranked yet" : "\(percentile!)th percentile among active ball knowers, \(viewModel.statsRange.label.lowercased())"
        )
    }

    private var gamerTiles: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
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
            streakTile
        }
    }

    /// The Gamer half's answer to `standingTile` — same full-width, richer
    /// row, so switching tabs doesn't leave Gamer feeling like the thinner
    /// half of the toggle.
    private var streakTile: some View {
        let streak = viewModel.gamerHighlight.currentStreak
        return VStack(alignment: .leading, spacing: 10) {
            Text("Current streak").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            HStack(spacing: 16) {
                StreakDots(streak: streak)
                Text(
                    streak == 0
                        ? "Win your next multiplayer game to start one"
                        : "\(streak) consecutive \(streak == 1 ? "win" : "wins")"
                )
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streak == 0 ? "No current win streak" : "\(streak) game win streak")
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

/// The Gamer half's counterpart to `PercentileRing` — a win streak has no
/// natural 0–100 gauge, so it reads as filled beads instead, capped at 5 so a
/// long streak doesn't stretch the row; the count alongside always says the
/// real number.
private struct StreakDots: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            if streak == 0 {
                Circle().strokeBorder(Theme.line, lineWidth: 1).frame(width: 14, height: 14)
            } else {
                ForEach(0..<min(streak, 5), id: \.self) { _ in
                    Circle().fill(Theme.hiddenText).frame(width: 14, height: 14)
                }
            }
        }
        .frame(minWidth: 64, alignment: .leading)
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
