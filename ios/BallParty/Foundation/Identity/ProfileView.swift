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
    @State private var privacy: PrivacySettingsViewModel?
    @State private var showFriends = false
    @State private var showNotifications = false
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

    /// Friends, editing, privacy, support and the way out. It sits opposite the
    /// bell in the header, so it is a button the same size.
    private var profileMenu: some View {
        Menu {
            Button {
                showFriends = true
            } label: {
                Label("Friends", systemImage: "person.2")
            }
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
            Button {
                privacy = PrivacySettingsViewModel(
                    client: profileClient, isPrivate: viewModel.profile?.isPrivate ?? false
                )
            } label: {
                Label("Privacy", systemImage: "lock")
            }
            Button {
                showNotifications = true
            } label: {
                Label("Notifications", systemImage: "bell")
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
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Profile menu")
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
        .screenHeader("Profile") {
            profileMenu
        } trailing: {
            RootBell()
        }
        .navigationDestination(isPresented: $showFriends) { FriendsView() }
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
        .sheet(isPresented: $showNotifications) {
            PushSettingsView(coordinator: .shared)
                .presentationDetents([.medium])
                .presentationBackground(Theme.surface)
        }
        .sheet(item: $privacy, onDismiss: { Task { await viewModel.load() } }) { privacyViewModel in
            PrivacySettingsView(viewModel: privacyViewModel)
                .presentationDetents([.medium])
                .presentationBackground(Theme.surface)
        }
        .task {
            await viewModel.load()
            await huddle.load()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Avatar(name: viewModel.displayName, url: viewModel.avatarURL)

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

// MARK: - Privacy

/// The privacy setting, opened from the Profile menu.
private struct PrivacySettingsView: View {
    @ObservedObject var viewModel: PrivacySettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Privacy").slabTitle(34)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.quiet)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Private profile",
                    isOn: Binding(
                        get: { viewModel.isPrivate },
                        set: { value in Task { await viewModel.set(value) } }
                    )
                )
                .disabled(viewModel.isSaving)
                .tint(Theme.hiddenText)

                Text(PrivacySettingsViewModel.explanation)
                    .font(.sans(14))
                    .foregroundStyle(Theme.fgMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well()

            if let notice = viewModel.notice {
                Text(notice).font(.sans(14)).foregroundStyle(Theme.hiddenText)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .screenBackground()
    }
}

// MARK: - Profile stats

/// The signed-in player's stats: the shared `StatsCard`, plus a link to the
/// leaderboard on whichever range the card is showing.
private struct HighlightsCard: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        StatsCard(
            title: "Your stats",
            statsView: $viewModel.statsView,
            statsRange: $viewModel.statsRange,
            knower: viewModel.selectedKnowerHighlight,
            status: viewModel.knowerStatus,
            statusDetail: viewModel.knowerStatusDetail,
            gamer: viewModel.gamerHighlight,
            unrankedStandingText: "Make a correct pick to enter the rankings",
            noStreakText: "Win your next multiplayer game to start one"
        ) {
            leaderboardLink
        }
    }

    /// Opens the leaderboard on whichever range the card is showing. Part of
    /// the Ball Knower half, so the Gamer half never offers it.
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
}


// MARK: - Take history

/// "Your takes" — every top-level comment the viewer has left on a Huddle
/// prompt, newest first, as the same take cards the prompt screen shows: picks fold
/// away, the reply row opens the thread and the strip opens the prompt.
private struct TakesHistory: View {
    @ObservedObject var huddle: HuddleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Your takes")

            switch huddle.phase {
            case .loading:
                LoadingSpinner().frame(maxWidth: .infinity, alignment: .center)
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
                    // The reply row opens the thread, the strip opens the prompt and
                    // "View take" folds the picks, so no card-wide link: it would fight
                    // them for the tap, as in the prompt screen.
                    TakeCardView(
                        post: take.post,
                        comment: take.comment,
                        showsReplyCount: true,
                        collapsesPicks: true,
                        threadDestination: { AnyView(TakeThreadView(viewModel: huddle, postId: take.post.id, takeId: take.comment.id)) },
                        contextTitle: take.post.caption.trimmingCharacters(in: .whitespaces).isEmpty ? "a prompt" : take.post.caption,
                        contextDestination: { AnyView(PromptDetailView(viewModel: huddle, postId: take.post.id)) }
                    )
                }
            }
        }
    }
}
