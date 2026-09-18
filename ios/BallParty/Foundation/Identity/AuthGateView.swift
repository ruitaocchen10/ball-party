import SwiftUI

/// The gate every other iOS feature builds behind: no session, no app. There
/// is no guest path here, unlike the web — see `AuthViewModel`.
struct AuthGateView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        Group {
            if viewModel.session != nil {
                ContentView(viewModel: viewModel)
            } else {
                AuthView(viewModel: viewModel)
            }
        }
    }
}
