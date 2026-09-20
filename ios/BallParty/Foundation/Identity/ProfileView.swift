import SwiftUI

/// The Profile tab: who is signed in, and the way out. The web's `/profile`
/// carries a player's history and highlights too; those are not on iOS yet.
struct ProfileView: View {
    @ObservedObject var auth: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    init(auth: AuthViewModel, viewerId: UUID, email: String?) {
        self.auth = auth
        _viewModel = StateObject(
            wrappedValue: ProfileViewModel(
                client: SupabaseProfileClient(client: SupabaseConfig.client),
                userId: viewerId,
                email: email
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Button("Sign out") {
                    Task { await auth.signOut() }
                }
                .buttonStyle(.ghost)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
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
