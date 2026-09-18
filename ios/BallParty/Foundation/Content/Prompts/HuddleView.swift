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
                ProgressView("Loading the feed…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load Huddle", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.load() } }
                }
            case .loaded:
                feed
            }
        }
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
            ContentUnavailableView(
                "No prompts yet",
                systemImage: "text.bubble",
                description: Text("New prompts show up here. Pull down to check again.")
            )
            .refreshable { await viewModel.load() }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
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
                .padding()
            }
            .refreshable { await viewModel.load() }
        }
    }
}

/// A prompt as the feed shows it: enough of the matchup to invite a response,
/// with the picks and the takes behind the tap.
private struct PostCard: View {
    let post: PromptPost
    let actionLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.promptText)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                PostStatusLabel(post: post)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !post.caption.isEmpty {
                Text(post.caption).font(.subheadline).foregroundStyle(.secondary)
            }
            if post.status == .void, let reason = post.voidReason {
                Text(reason).font(.caption.monospaced()).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(post.slots.prefix(3)) { slot in
                    Text(matchup(slot)).font(.subheadline.weight(.medium))
                }
                if post.slots.count > 3 {
                    Text("+\(post.slots.count - 3) more").font(.caption).foregroundStyle(.secondary)
                }
            }

            if post.aggregate != nil {
                Text("\(post.responseCount) \(post.responseCount == 1 ? "person has" : "people have") answered")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(actionLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.tint, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .opacity(post.status == .void ? 0.5 : 1)
    }

    private func matchup(_ slot: PromptSlot) -> String {
        slot.options.map(\.label).joined(separator: " vs ")
    }
}
