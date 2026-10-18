import SwiftUI

/// Holds the link the Home invite bar shares. The bar has no dismiss, so the
/// only state is whether the invite code has been read yet.
@MainActor
final class InviteBarViewModel: ObservableObject {
    @Published private(set) var inviteURL: URL?

    private let client: FriendsClient

    init(client: FriendsClient) {
        self.client = client
    }

    /// Reads the invite code once. A failed read leaves the bar hidden until the next load.
    func load() async {
        guard inviteURL == nil else { return }
        guard let code = try? await client.inviteCode() else { return }
        inviteURL = FriendInviteLink.url(code: code)
    }
}

/// A one-row bar below the Home filter pills that shares the player's friend invite link.
/// It is the light card (`Theme.fg`), so it stands out from the dark panels around it.
struct InviteBar: View {
    @ObservedObject var viewModel: InviteBarViewModel

    var body: some View {
        if let url = viewModel.inviteURL {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite your friends")
                        .font(.slab(22, relativeTo: .headline))
                        .tracking(0.88)
                        .textCase(.uppercase)
                    Text("Send your link to friends.")
                        .font(.sans(13))
                        .foregroundStyle(Theme.surface.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ShareLink(item: url, message: Text("Add me on Ball Party.")) {
                    Text("Invite")
                }
                .buttonStyle(BPButtonStyle(variant: .dark, size: .sm, fullWidth: false))
            }
            .foregroundStyle(Theme.surface)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.fg)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.surface.opacity(0.15), lineWidth: 1))
            // 20pt above (the feed's card spacing) and, with the feed's own 16pt, 20pt below.
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 4)
        }
    }
}
