import SwiftUI

/// The sheet a friend invite link opens: "X invited you" with an Add friend
/// button. Opening the link sends nothing; the tap does, and the owner still
/// accepts. Same states and copy as the web's `FriendInviteCard`.
struct FriendInviteView: View {
    @StateObject private var viewModel: FriendInviteViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        code: String,
        client: FriendsClient = SupabaseFriendsClient(client: SupabaseConfig.client)
    ) {
        _viewModel = StateObject(wrappedValue: FriendInviteViewModel(client: client, code: code))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .frame(maxWidth: .infinity)
                .padding(16)
        }
        .screenBackground()
        .navigationTitle("Friend invite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .unavailable:
            EmptyState(title: FriendInviteViewModel.unavailableTitle, message: FriendInviteViewModel.unavailableMessage)
        case .failed(let message):
            EmptyState(title: "Couldn’t load this invite", message: message) {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        case .loaded(let owner):
            Portrait(name: owner.player.displayName, url: owner.player.avatarURL, size: 64)
            Text("Friend invite").monoLabel(10, tracking: 0.12)
            Text("\(owner.player.displayName) invited you")
                .slabTitle(34)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(owner.player.handle)
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
            if let result = viewModel.result {
                Text(FriendInviteViewModel.copy(for: result))
                    .font(.sans(15))
                    .foregroundStyle(Theme.fg)
            } else {
                Button(viewModel.isSending ? "Sending…" : "Add friend") {
                    Task { await viewModel.addFriend() }
                }
                .buttonStyle(.solid)
                .disabled(viewModel.isSending)
            }
            if let error = viewModel.error {
                Text(error).font(.sans(14)).foregroundStyle(Theme.hiddenText)
            }
        }
    }
}
