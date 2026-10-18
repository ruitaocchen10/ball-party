import SwiftUI
import UIKit

/// How people get into a room from an open seat: the room link, for anyone, and
/// a friend picker. Mirrors the web's `InviteFriendsModal` for the picker: each
/// friend gets an Invite button, then the server's answer as a badge.
struct InviteFriendsSheet: View {
    @StateObject private var viewModel: InviteFriendsViewModel
    @Environment(\.dismiss) private var dismiss
    private let roomCode: String
    @State private var copied = false

    init(
        lobbyId: UUID,
        roomCode: String,
        friendsClient: FriendsClient = SupabaseFriendsClient(client: SupabaseConfig.client),
        invitesClient: RoomInvitesClient = SupabaseRoomInvitesClient(client: SupabaseConfig.client)
    ) {
        self.roomCode = roomCode
        _viewModel = StateObject(
            wrappedValue: InviteFriendsViewModel(
                lobbyId: lobbyId, friendsClient: friendsClient, invitesClient: invitesClient
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    link
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(text: "Friends")
                        Text("They'll get the invite on their Party tab and can join straight from there.")
                            .font(.sans(14))
                            .foregroundStyle(Theme.fgMuted)
                        content
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await viewModel.load() }
        }
    }

    /// The room link, for anyone who isn't a friend on Ball Party yet.
    private var link: some View {
        let url = RoomLink.url(code: roomCode)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Invite link").fieldLabel()
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(Theme.fgMuted)
                    .accessibilityHidden(true)
                Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .monoLabel(14, weight: .semibold, tracking: 0, color: Theme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .fieldStyle()
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.url = url
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(BPButtonStyle(variant: copied ? .ghost : .solid))
                ShareLink(item: url, message: Text("Join my Ball Party room")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BPButtonStyle(variant: .ghost))
            }
            Text("Anyone with the link can join while there is an open seat.")
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            EmptyState(title: "Couldn’t load your friends", message: message) {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        case .loaded where viewModel.friends.isEmpty:
            EmptyState(
                title: "No friends yet",
                message: "Add friends from Profile, then Friends, and you can invite them here."
            )
        case .loaded:
            VStack(spacing: 0) {
                ForEach(viewModel.friends) { friend in
                    VStack(spacing: 0) {
                        LineRule()
                        row(friend).padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func row(_ friend: Friend) -> some View {
        let attempt = viewModel.attempts[friend.id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PersonRow(player: friend.player)
                switch attempt {
                case .result(let result):
                    Text(result.label)
                        .monoLabel(10, weight: .bold, tracking: 0.08,
                                   color: result == .invited ? Theme.fg : Theme.fgMuted)
                        .accessibilityLabel("\(result.label). \(result.detail)")
                default:
                    EmptyView()
                }
                if !isSettled(attempt) {
                    Button {
                        Task { await viewModel.invite(friend) }
                    } label: {
                        Text(buttonTitle(attempt))
                    }
                    .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                    .disabled(attempt == .sending)
                    .accessibilityLabel("Invite \(friend.player.displayName)")
                }
            }
            if case .failed(let message) = attempt {
                Text(message).font(.sans(12)).foregroundStyle(Theme.hiddenText)
            }
        }
    }

    private func isSettled(_ attempt: InviteFriendsViewModel.Attempt?) -> Bool {
        if case .result(let result) = attempt { return result.isSettled }
        return false
    }

    private func buttonTitle(_ attempt: InviteFriendsViewModel.Attempt?) -> String {
        switch attempt {
        case .sending: "Inviting…"
        case .none: "Invite"
        default: "Try again"
        }
    }
}

/// "Room invites": pending invites from friends, with Join and Decline.
/// Renders nothing when there are none.
struct RoomInvitesInboxSection: View {
    @ObservedObject var viewModel: RoomInvitesInboxViewModel
    /// Whether the player is already in a room: joining another leaves it.
    var hasRoom: Bool
    /// Called with the room an accepted invite put the player in.
    var onJoined: (Lobby) -> Void

    var body: some View {
        if !viewModel.invites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Room invites")
                if hasRoom {
                    Text("Heads up: joining an invite leaves the room you're in.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.fgMuted)
                }
                ForEach(viewModel.invites) { invite in
                    VStack(spacing: 0) {
                        LineRule()
                        row(invite).padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func row(_ invite: RoomInvite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Avatar(name: invite.senderName, url: invite.senderAvatarURL, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(invite.senderName) invited you")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(invite.summary)
                        .font(.sans(14))
                        .foregroundStyle(Theme.fgMuted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Decline") {
                    Task { await viewModel.decline(invite) }
                }
                .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                .disabled(viewModel.isBusy)
                .accessibilityLabel("Decline invite from \(invite.senderName)")
                Button {
                    Task {
                        if let lobby = await viewModel.accept(invite) { onJoined(lobby) }
                    }
                } label: {
                    Text(viewModel.busyInviteId == invite.id && viewModel.busyAction == .accept ? "Joining…" : "Join")
                }
                .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                .disabled(viewModel.isBusy)
                .accessibilityLabel("Join \(invite.senderName)'s room")
            }
            if let message = viewModel.errors[invite.id] {
                Text(message).font(.sans(12)).foregroundStyle(Theme.hiddenText)
            }
        }
    }
}
