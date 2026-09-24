import SwiftUI

/// A placeholder for a tab whose real screen isn't built yet: an `EmptyState`
/// saying so plainly rather than showing a half-built feature, under the
/// native navigation title. Generic on purpose, so any tab can point at it
/// without a bespoke "coming soon" of its own.
struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            EmptyState(title: "Coming soon", message: message)
                .padding(16)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
