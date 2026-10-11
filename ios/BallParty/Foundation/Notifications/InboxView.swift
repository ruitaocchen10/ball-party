import SwiftUI

/// The inbox the bell opens: friend requests, replies to your takes and room
/// invites. A request or invite can be answered in place; a request opens the
/// player's profile and a reply opens the take. Nothing here decides what is
/// valid: the view model shows the server's state and re-reads after every
/// action.
struct InboxView: View {
    @ObservedObject var viewModel: InboxViewModel
    let viewerId: UUID
    /// Called with the room an accepted invite put the player in.
    var onJoined: (Lobby) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination: InboxDestination?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.items.isEmpty {
                        EmptyState(
                            title: "You're all caught up",
                            message: "Friend requests, replies to your takes and room invites show up here."
                        )
                        .padding(16)
                    } else {
                        ForEach(viewModel.items) { item in
                            LineRule()
                            row(item).padding(.horizontal, 16).padding(.vertical, 12)
                        }
                    }
                }
            }
            .screenBackground()
            .refreshable { await viewModel.load() }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.unreadCount > 0 {
                        Button("Mark all read") { Task { await viewModel.markAllRead() } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .profile(let username):
                    OtherProfileView(username: username)
                case .take(let postId, let takeId):
                    TakeThreadLoader(viewerId: viewerId, postId: postId, takeId: takeId)
                }
            }
            .task { await viewModel.load() }
        }
    }

    private func row(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard let target = item.destination else { return }
                Task { await viewModel.markRead(item) }
                destination = target
            } label: {
                HStack(spacing: 12) {
                    Avatar(name: item.actorName, url: item.actorAvatarURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.sans(16, weight: .semibold))
                            .foregroundStyle(item.isDead ? Theme.fgMuted : Theme.fg)
                            .multilineTextAlignment(.leading)
                        if let detail = item.detail {
                            Text(detail).font(.sans(14)).foregroundStyle(Theme.fgMuted)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.isUnread {
                        Circle().fill(Theme.hiddenText).frame(width: 8, height: 8)
                            .accessibilityLabel("Unread")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.destination == nil)

            if item.hasActions {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Decline") { Task { await viewModel.decline(item) } }
                        .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                        .disabled(viewModel.isBusy)
                        .accessibilityLabel("Decline \(item.actorName)")
                    Button {
                        Task {
                            if let lobby = await viewModel.accept(item) {
                                dismiss()
                                onJoined(lobby)
                            }
                        }
                    } label: {
                        Text(item.kind == .roomInvite ? "Join" : "Accept")
                    }
                    .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                    .disabled(viewModel.isBusy)
                    .accessibilityLabel(
                        item.kind == .roomInvite ? "Join \(item.actorName)'s room" : "Accept \(item.actorName)"
                    )
                }
            }
            if let message = viewModel.errors[item.key] {
                Text(message).font(.sans(12)).foregroundStyle(Theme.hiddenText)
            }
        }
    }
}

/// A take opened from the inbox. The Home tab owns the Huddle's feed, so this
/// reads its own copy of the posts, then shows the same thread screen.
private struct TakeThreadLoader: View {
    @StateObject private var viewModel: HuddleViewModel
    let postId: UUID
    let takeId: UUID

    init(viewerId: UUID, postId: UUID, takeId: UUID) {
        self.postId = postId
        self.takeId = takeId
        _viewModel = StateObject(
            wrappedValue: HuddleViewModel(client: SupabaseHuddleClient(client: SupabaseConfig.client), viewerId: viewerId)
        )
    }

    var body: some View {
        TakeThreadView(viewModel: viewModel, postId: postId, takeId: takeId)
            .task { await viewModel.load() }
    }
}
