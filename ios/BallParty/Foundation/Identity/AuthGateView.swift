import SwiftUI

/// The gate every other iOS feature builds behind: no session, no app. There
/// is no guest path here, unlike the web — see `AuthViewModel`.
struct AuthGateView: View {
    @StateObject private var viewModel = AuthViewModel()
    /// A friend invite code from a link the app was opened with. Held until
    /// there is a session, then shown as a sheet (the web sends signed-out
    /// visitors through login and back; this is the same trip).
    @State private var inviteCode: String?
    /// A room code from a room link, held until there is a session and then
    /// handed to the Party tab to join.
    @State private var roomCode: String?

    var body: some View {
        Group {
            if viewModel.session != nil {
                MainTabView(viewModel: viewModel, pendingRoomCode: $roomCode)
            } else {
                AuthView(viewModel: viewModel)
            }
        }
        .onOpenURL(perform: receive)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { receive(url) }
        }
        .sheet(item: Binding(
            get: { viewModel.session == nil ? nil : inviteCode.map(InviteRoute.init) },
            set: { if $0 == nil { inviteCode = nil } }
        )) { route in
            NavigationStack { FriendInviteView(code: route.code) }
        }
    }

    private func receive(_ url: URL) {
        if let code = FriendInviteLink.code(from: url) { inviteCode = code }
        else if let code = RoomLink.code(from: url) { roomCode = code }
    }

    private struct InviteRoute: Identifiable {
        let code: String
        var id: String { code }
    }
}
