import SwiftUI

/// Entry point for Huddle: owns the view model and shows the feed.
struct HuddleScreen: View {
    @StateObject private var viewModel: HuddleViewModel

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: HuddleViewModel(
                client: SupabaseHuddleClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
    }

    var body: some View {
        HuddleFeedView(viewModel: viewModel)
    }
}

struct HuddleFeedView: View {
    @ObservedObject var viewModel: HuddleViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView {
                    Text("Loading the feed…").monoLabel(11, tracking: 0.15)
                }
            case .failed(let message):
                ScrollView {
                    EmptyState(title: "Couldn't load Huddle", message: message) {
                        Button("Try again") { Task { await viewModel.load() } }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                    }
                    .padding(16)
                }
            case .loaded:
                feed
            }
        }
        .screenBackground()
        .navigationTitle("Huddle")
        .navigationBarTitleDisplayMode(.inline)
        // Also runs on coming back from a prompt, which is when the feed is
        // most likely to be stale (a pick was just locked in).
        .task { await viewModel.load() }
        // Huddle has no live channel, so returning to the app is the moment to
        // look again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.load() } }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if viewModel.posts.isEmpty {
            ScrollView {
                EmptyState(
                    title: "No prompts yet",
                    message: "New prompts show up here. Pull down to check again."
                )
                .padding(16)
            }
            .refreshable { await viewModel.load() }
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }
                    ForEach(viewModel.posts) { post in
                        NavigationLink {
                            PromptDetailView(viewModel: viewModel, postId: post.id)
                        } label: {
                            PostCard(post: post, actionLabel: viewModel.callToAction(for: post.id).label)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .refreshable { await viewModel.load() }
        }
    }
}

/// A prompt as the feed shows it: enough of the matchup to invite a response,
/// with the picks and the takes behind the tap.
///
/// It is a panel because a prompt is the thing that matters here. The red edge
/// is there while the crowd's answer is still withheld from this viewer —
/// `aggregate` is nil until they have answered.
private struct PostCard: View {
    let post: PromptPost
    let actionLabel: String

    var body: some View {
        PanelCard(edge: post.aggregate == nil) {
            VStack(alignment: .leading, spacing: 10) {
                PostStatusLabel(post: post)
                    .monoLabel(10, tracking: 0.16, color: Theme.hiddenInk)

                Text(post.promptText)
                    .slabTitle(30, color: Theme.panelFg)
                    .lineSpacing(0)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.sans(15))
                        .foregroundStyle(Theme.panelBody)
                }
                if post.status == .void, let reason = post.voidReason {
                    Text(reason).monoLabel(11, tracking: 0.08, color: Theme.panelMuted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(post.slots.prefix(3)) { slot in
                        Text(matchup(slot)).font(.sans(15, weight: .semibold))
                    }
                    if post.slots.count > 3 {
                        Text("+\(post.slots.count - 3) more").monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                    }
                }

                DashedRule().padding(.top, 4)

                HStack {
                    if post.aggregate != nil {
                        Text("\(post.responseCount) \(post.responseCount == 1 ? "person has" : "people have") answered")
                            .monoLabel(10, tracking: 0.11, color: Theme.panelMuted)
                    }
                    Spacer()
                    Text(actionLabel)
                        .font(.slab(16, relativeTo: .body))
                        .tracking(0.64)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.panel)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.panelFg)
                }
            }
            .padding(16)
        }
        .opacity(post.status == .void ? 0.5 : 1)
    }

    private func matchup(_ slot: PromptSlot) -> String {
        slot.options.map(\.label).joined(separator: " vs ")
    }
}
